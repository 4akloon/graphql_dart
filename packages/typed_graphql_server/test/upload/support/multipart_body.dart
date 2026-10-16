import 'dart:convert';

/// A builder of `multipart/form-data` bodies for the upload tests.
final class MultipartBody {
  MultipartBody({String boundary = 'testBoundary'})
    : this._(boundary, const []);

  MultipartBody._(this.boundary, this._parts);

  final String boundary;
  final List<List<int>> _parts;

  /// The `content-type` header of a request with this body.
  String get contentType => 'multipart/form-data; boundary=$boundary';

  /// A text field.
  MultipartBody field(String name, String value) => rawPart(
    'content-disposition: form-data; name="$name"',
    utf8.encode(value),
  );

  /// A field whose content is arbitrary bytes.
  MultipartBody fieldBytes(String name, List<int> content) =>
      rawPart('content-disposition: form-data; name="$name"', content);

  /// A file part; a null [contentType] leaves the header out.
  MultipartBody file(
    String name,
    List<int> content, {
    String? filename = 'file.txt',
    String? contentType = 'text/plain',
  }) => rawPart(
    [
      'content-disposition: form-data; name="$name"'
          '${filename == null ? '' : '; filename="$filename"'}',
      ?(contentType == null ? null : 'content-type: $contentType'),
    ].join('\r\n'),
    content,
  );

  /// A part with exactly [headers] (lines joined by CRLF, without the blank
  /// line) and [content].
  MultipartBody rawPart(String headers, List<int> content) =>
      MultipartBody._(boundary, [
        ..._parts,
        [
          ...utf8.encode('--$boundary\r\n$headers\r\n\r\n'),
          ...content,
          ...utf8.encode('\r\n'),
        ],
      ]);

  /// The whole body, with the closing delimiter.
  List<int> get bytes => [
    for (final part in _parts) ...part,
    ...utf8.encode('--$boundary--\r\n'),
  ];

  /// The body split in chunks of [chunkSize] bytes, or in one chunk when it
  /// is null.
  Stream<List<int>> stream({int? chunkSize, List<int>? source}) {
    final all = source ?? bytes;
    if (chunkSize == null) return Stream.value(all);
    return Stream.fromIterable([
      for (var start = 0; start < all.length; start += chunkSize)
        all.sublist(
          start,
          start + chunkSize > all.length ? all.length : start + chunkSize,
        ),
    ]);
  }
}

/// The failure of a request body whose connection broke.
final class ConnectionReset implements Exception {
  const ConnectionReset();
}
