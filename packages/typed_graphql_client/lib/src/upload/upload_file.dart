import 'dart:typed_data';

/// A file sent as the value of an `Upload` variable, following the GraphQL
/// multipart request specification (R8.4).
///
/// The generated variables hold the file's [marker] in its place, through
/// `UploadFileCodec`; the caller lists the files of a request in an
/// `UploadFiles` context entry, and `HttpLink` sends them as parts of a
/// `multipart/form-data` body.
///
/// {@category upload}
final class UploadFile {
  /// A file of [bytes], copied.
  ///
  /// [filename] and [contentType] must not contain a carriage return, a
  /// line feed or a double quote, which would break the part's headers.
  UploadFile.fromBytes(
    List<int> bytes, {
    required this.filename,
    this.contentType = defaultContentType,
  }) : length = bytes.length,
       marker = _nextMarker(),
       _open = _opener(Uint8List.fromList(bytes)) {
    _check(filename, contentType);
  }

  /// A file whose content [open] streams, [length] bytes long. [open] is
  /// called once per attempt, so a retried request sends the file again.
  /// [length] must not be negative; [filename] and [contentType] follow the
  /// rule of [UploadFile.fromBytes].
  UploadFile.fromStream(
    Stream<List<int>> Function() open, {
    required this.length,
    required this.filename,
    this.contentType = defaultContentType,
  }) : marker = _nextMarker(),
       _open = open {
    RangeError.checkNotNegative(length, 'length');
    _check(filename, contentType);
  }

  /// The content type of a file created without one.
  static const String defaultContentType = 'application/octet-stream';

  /// The prefix of every [marker].
  static const String markerPrefix = 'typed_graphql.upload/';

  static int _markerCount = 0;

  /// The file name sent in the part's `Content-Disposition`.
  final String filename;

  /// The part's `Content-Type`.
  final String contentType;

  /// The content's length in bytes.
  final int length;

  /// The string the generated variables hold in this file's place, unique
  /// to this object.
  final String marker;

  final Stream<List<int>> Function() _open;

  /// The content, from the start; a new stream on every call.
  Stream<List<int>> open() => _open();

  static void _check(String filename, String contentType) {
    for (final (name, value) in [
      ('filename', filename),
      ('contentType', contentType),
    ]) {
      if (value.contains(RegExp(r'[\r\n"]'))) {
        throw ArgumentError.value(
          value,
          name,
          'must not contain a line break or a double quote',
        );
      }
    }
  }

  static String _nextMarker() => '$markerPrefix${_markerCount++}';

  static Stream<List<int>> Function() _opener(Uint8List bytes) =>
      () => Stream.value(bytes);

  @override
  String toString() => 'UploadFile($filename, $length bytes)';
}
