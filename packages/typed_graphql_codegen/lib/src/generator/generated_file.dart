/// A file the generator writes.
///
/// {@category codegen}
final class const GeneratedFile(
  /// The path relative to the configuration file, with `/` separators.
  final String path,

  /// The content of the file.
  final String text,
) {
  /// Creates a file.
  this;

  @override
  bool operator ==(Object other) =>
      other is GeneratedFile && other.path == path && other.text == text;

  @override
  int get hashCode => Object.hash(path, text);

  @override
  String toString() => 'GeneratedFile($path)';
}
