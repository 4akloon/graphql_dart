import 'package:meta/meta.dart';

import 'path_segment.dart';

/// The result of reading untrusted input: a value, or why there is none.
///
/// Decoding never throws on bad input (spec §0, principle 3): a caller
/// switches over [DecodeSuccess] and [DecodeFailure].
///
/// {@category protocol}
@immutable
sealed class const DecodeResult<T>() {
  /// Creates a result.
  this;

  /// This result with a failure placed inside [segment] of its parent; a
  /// success is returned as it is.
  DecodeResult<T> inside(PathSegment segment) => switch (this) {
    DecodeSuccess() => this,
    DecodeFailure(:final message, :final path) => DecodeFailure(
      message,
      path: List.unmodifiable([segment, ...path]),
    ),
  };
}

/// Decoding produced [value].
///
/// {@category protocol}
final class const DecodeSuccess<T>(
  /// The decoded value.
  final T value,
) extends DecodeResult<T> {
  /// Creates a success.
  this;

  @override
  bool operator ==(Object other) =>
      other is DecodeSuccess<Object?> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DecodeSuccess($value)';
}

/// Decoding failed: [message] says what is wrong, [path] where.
///
/// {@category protocol}
final class const DecodeFailure(
  /// What is wrong, such as `expected a string`.
  final String message, {

  /// The keys and indexes from the root of the input to the bad value;
  /// empty when the root itself is bad.
  final List<PathSegment> path = const [],
}) extends DecodeResult<Never> {
  /// Creates a failure.
  this;

  @override
  bool operator ==(Object other) =>
      other is DecodeFailure &&
      other.message == message &&
      _isSamePath(other.path);

  @override
  int get hashCode => Object.hash(message, Object.hashAll(path));

  /// The path as JSONPath and the message: `$.errors[0].message: expected
  /// a string`.
  @override
  String toString() {
    final where = StringBuffer(r'$');
    for (final segment in path) {
      where.write(switch (segment) {
        PathKey(:final name) => '.$name',
        PathIndex(:final index) => '[$index]',
      });
    }
    return '$where: $message';
  }

  /// Whether [other] has the steps of [path], in the same order.
  bool _isSamePath(List<PathSegment> other) {
    if (other.length != path.length) {
      return false;
    }
    for (var i = 0; i < path.length; i++) {
      if (other[i] != path[i]) {
        return false;
      }
    }
    return true;
  }
}
