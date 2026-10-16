/// A file a client sent with a multipart request, as a resolver reads it.
///
/// An upload is valid only during the request that carried it: the storage
/// may delete the file as soon as the response is built, so a resolver reads
/// it before it returns and keeps neither the [Upload] nor its stream.
///
/// {@category upload}
abstract interface class Upload {
  /// The file name the client gave the part, or the empty string.
  ///
  /// It is untrusted client text of at most 255 characters: it may hold path
  /// separators, `..` or control characters, so never use it as a path.
  String get filename;

  /// The media type the client gave the part, `application/octet-stream` when
  /// it gave none.
  ///
  /// It is untrusted client text of at most 127 characters, not a checked
  /// media type, and says nothing about what the bytes are.
  String get mediaType;

  /// The number of bytes of the file.
  int get length;

  /// Opens the file's content for reading; every call starts at the first
  /// byte.
  Stream<List<int>> openRead();
}
