import '../link/context_entry.dart';
import 'upload_file.dart';

/// The files of one request, listed by the caller in its context so that
/// `HttpLink` can find the object behind each marker of the variables.
///
/// Links that cannot send files (`WebSocketLink`, `SseLink`) answer a
/// request with this entry with an `UnsupportedOperation`.
///
/// {@category upload}
final class UploadFiles extends ContextEntry {
  /// Creates the entry for [files], copied.
  UploadFiles(Iterable<UploadFile> files) : files = List.unmodifiable(files);

  /// The files, in the order given.
  final List<UploadFile> files;

  /// The file whose marker is [marker], or null.
  UploadFile? withMarker(String marker) {
    for (final file in files) {
      if (file.marker == marker) {
        return file;
      }
    }
    return null;
  }

  @override
  String toString() => 'UploadFiles($files)';
}
