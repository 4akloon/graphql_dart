import 'upload.dart';

/// Where the files of a multipart request wait until the response is built.
///
/// The storage owns the bytes: the transport streams each file into [store]
/// and calls [release] once per stored upload, after the response is built,
/// whatever happened.
///
/// {@category upload}
abstract interface class UploadStorage {
  /// Stores the [content] of one file and returns the [Upload] that reads it
  /// back.
  ///
  /// [filename] and [mediaType] are what the client wrote, unchecked and
  /// bounded only in length (255 and 127 characters): generate your own file
  /// names and never use [filename] as a path.
  ///
  /// An exception that [store] throws for any other reason than [content]
  /// failing is a fault of the server: the request is answered with `500`.
  ///
  /// When [content] fails, which is how a file over its limit is reported,
  /// drop whatever was written and let the error through.
  Future<Upload> store(
    String filename,
    String mediaType,
    Stream<List<int>> content,
  );

  /// Frees what [store] kept for [upload].
  ///
  /// It is called once per stored upload, and it must not throw for an upload
  /// it does not know.
  Future<void> release(Upload upload);
}
