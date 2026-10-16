import 'package:typed_graphql_server/typed_graphql_server.dart';

/// What a storage throws when it cannot release a file.
final class ReleaseFailed implements Exception {
  const ReleaseFailed();
}

/// A storage that wraps [MemoryUploadStorage] and counts what it is asked.
final class CountingStorage implements UploadStorage {
  CountingStorage({
    this.releaseThrows = false,
    this.storeFailure,
    this.failingCall = 1,
  });

  /// What [store] throws on call number [failingCall], or null to never fail.
  final Exception? storeFailure;

  /// The 1-based call of [store] that throws [storeFailure].
  final int failingCall;

  int _calls = 0;

  /// Whether [release] throws after it forgot the upload.
  final bool releaseThrows;

  final UploadStorage _inner = const MemoryUploadStorage();
  final List<Upload> _held = [];

  /// How many files were stored completely.
  int stored = 0;

  /// How many files were released.
  int released = 0;

  /// How many [store] calls failed.
  int failed = 0;

  /// The names the files were stored with, in order.
  final List<String> filenames = [];

  /// The media types the files were stored with, in order.
  final List<String> mediaTypes = [];

  /// The uploads stored and not released yet.
  List<Upload> get held => List.unmodifiable(_held);

  @override
  Future<Upload> store(
    String filename,
    String mediaType,
    Stream<List<int>> content,
  ) async {
    filenames.add(filename);
    mediaTypes.add(mediaType);
    _calls++;
    final failure = storeFailure;
    try {
      if (_calls == failingCall && failure != null) throw failure;
      final upload = await _inner.store(
        filename,
        mediaType,
        content.asyncMap((chunk) async {
          // A turn of the event loop per chunk, as a storage that writes to disk.
          await Future<void>.delayed(Duration.zero);
          return chunk;
        }),
      );
      stored++;
      _held.add(upload);
      return upload;
    } on Exception {
      failed++;
      rethrow;
    }
  }

  @override
  Future<void> release(Upload upload) async {
    released++;
    _held.remove(upload);
    if (releaseThrows) throw const ReleaseFailed();
  }
}
