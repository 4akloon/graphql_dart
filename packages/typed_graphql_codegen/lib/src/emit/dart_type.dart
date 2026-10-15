/// A Dart type as written in generated code, with the codec that reads and
/// writes its values.
///
/// {@category codegen}
final class const DartType(
  /// The type as written, such as `List<String>?`.
  final String type,

  /// The constant expression of the codec, without `const` (it always stands
  /// in a constant context).
  final String codec,
) {
  /// Creates a type and its codec.
  this;

  @override
  bool operator ==(Object other) =>
      other is DartType && other.type == type && other.codec == codec;

  @override
  int get hashCode => Object.hash(type, codec);

  @override
  String toString() => 'DartType($type, $codec)';
}
