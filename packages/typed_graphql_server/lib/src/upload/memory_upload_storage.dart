import 'dart:typed_data';

import 'memory_upload.dart';
import 'upload.dart';
import 'upload_storage.dart';

/// An [UploadStorage] that keeps every file in memory.
///
/// It suits small files, and it is bounded by `UploadLimits.maxFileBytes` and
/// `UploadLimits.maxRequestBytes` per request. There is nothing to free, so
/// [release] does nothing: the bytes go with the [Upload].
///
/// {@category upload}
final class MemoryUploadStorage implements UploadStorage {
  /// Creates the storage.
  const MemoryUploadStorage();

  @override
  Future<Upload> store(
    String filename,
    String mediaType,
    Stream<List<int>> content,
  ) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in content) {
      bytes.add(chunk);
    }
    return MemoryUpload(filename, mediaType, bytes.takeBytes());
  }

  @override
  Future<void> release(Upload upload) async {}
}
