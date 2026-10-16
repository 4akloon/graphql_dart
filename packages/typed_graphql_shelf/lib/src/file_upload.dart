import 'dart:io';

import 'package:meta/meta.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

/// An [Upload] kept in a file that `TempFileUploadStorage` wrote.
@internal
final class FileUpload implements Upload {
  /// Describes the upload of [length] bytes kept in [file].
  const FileUpload(this.file, this.filename, this.mediaType, this.length);

  /// The file that holds the content.
  final File file;

  @override
  final String filename;

  @override
  final String mediaType;

  @override
  final int length;

  @override
  Stream<List<int>> openRead() => file.openRead();
}
