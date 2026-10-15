import 'dart_reference.dart';

/// How generated code holds a custom scalar (R7.8): its Dart [type] and the
/// [codec] that reads and writes it, a class with a const constructor that
/// implements `ScalarCodec<type>`.
///
/// {@category codegen}
final class const ScalarMapping(
  /// The Dart type of the scalar's values.
  final DartReference type,

  /// The codec class, constructed as `const Codec()` in generated code.
  final DartReference codec,
) {
  /// Creates a mapping to [type] through [codec].
  this;

  @override
  bool operator ==(Object other) =>
      other is ScalarMapping && other.type == type && other.codec == codec;

  @override
  int get hashCode => Object.hash(type, codec);
}
