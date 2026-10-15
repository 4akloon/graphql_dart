import 'package:typed_graphql/typed_graphql.dart';

/// A value of a response that does not have the shape the generated code
/// expects, and where it is.
///
/// Generated readers throw it; [DataCodec.decode] catches it and returns a
/// [DecodeFailure] with the same message and path, so it never leaves a
/// public `decode` (R0.3). Code outside generated libraries has no reason to
/// throw or catch it.
///
/// {@category operations}
final class DataFormatException implements Exception {
  /// Creates the exception for [message] at [path] (empty: the value being
  /// read).
  const DataFormatException(this.message, [this.path = const []]);

  /// What is wrong, as a sentence.
  final String message;

  /// Where the value is, from the value [DataCodec.decode] was given.
  final List<PathSegment> path;

  /// The same problem one level deeper: inside [segment] of its parent.
  DataFormatException inside(PathSegment segment) =>
      DataFormatException(message, [segment, ...path]);

  @override
  String toString() => 'DataFormatException: $message';
}
