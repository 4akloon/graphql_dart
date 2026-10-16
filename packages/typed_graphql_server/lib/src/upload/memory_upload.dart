import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'upload.dart';

/// An [Upload] whose bytes are in memory.
@internal
final class MemoryUpload implements Upload {
  /// Creates an upload of [bytes].
  const MemoryUpload(this.filename, this.mediaType, this.bytes);

  @override
  final String filename;

  @override
  final String mediaType;

  /// The content of the file.
  final Uint8List bytes;

  @override
  int get length => bytes.length;

  @override
  Stream<List<int>> openRead() => Stream.value(bytes);
}
