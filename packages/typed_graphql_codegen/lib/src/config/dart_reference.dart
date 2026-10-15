/// A Dart declaration the configuration names, such as the type or the codec
/// of a scalar: `package:my_app/codecs.dart#DateTimeCodec`, or the bare name
/// of a `dart:core` type such as `DateTime`.
///
/// {@category codegen}
final class const DartReference(
  /// The library that declares [name], such as
  /// `package:my_app/codecs.dart`; null for a `dart:core` type.
  final String? library,

  /// The declaration's name.
  final String name,
) {
  /// Creates a reference to [name] in [library].
  this;

  @override
  bool operator ==(Object other) =>
      other is DartReference && other.library == library && other.name == name;

  @override
  int get hashCode => Object.hash(library, name);

  @override
  String toString() => switch (library) {
    final library? => '$library#$name',
    null => name,
  };
}
