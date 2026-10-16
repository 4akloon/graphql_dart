/// The sizes a multipart request may reach (R5.6).
///
/// {@category upload}
final class UploadLimits {
  /// Creates the limits; the defaults suit a public endpoint.
  const UploadLimits({
    this.maxFiles = 10,
    this.maxFileBytes = 5242880,
    this.maxRequestBytes = 20971520,
    this.maxFieldBytes = 1048576,
  });

  /// The most files, and the most map paths, one request may name.
  final int maxFiles;

  /// The longest file accepted, in bytes.
  final int maxFileBytes;

  /// The longest request body accepted, in bytes, files included.
  final int maxRequestBytes;

  /// The longest `operations` or `map` field accepted, in bytes.
  final int maxFieldBytes;
}
