/// A file a client sent with a multipart request, as a resolver reads it.
///
/// An upload is valid only during the request that carried it: the storage
/// may delete the file as soon as the response is built, so a resolver reads
/// it before it returns and keeps neither the [Upload] nor its stream.
///
/// {@category upload}
abstract interface class Upload {
  /// The file name the client gave the part, or the empty string.
  String get filename;

  /// The media type the client gave the part, `application/octet-stream` when
  /// it gave none.
  String get mediaType;

  /// The number of bytes of the file.
  int get length;

  /// Opens the file's content for reading; every call starts at the first
  /// byte.
  Stream<List<int>> openRead();
}
