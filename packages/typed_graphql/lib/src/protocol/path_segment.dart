import 'package:meta/meta.dart';

/// One step of a path into a JSON value: a key of an object or an index of
/// an array.
///
/// A GraphQL error's `path` (spec §7.1.2, "response path") is a list of
/// them: response names and list indexes from the root of `data`. A
/// [DecodeFailure] uses the same steps to say where the bad value is.
///
/// {@category protocol}
@immutable
sealed class const PathSegment() {
  /// Creates a step.
  this;
}

/// A key of an object; in a response path, a response name (the alias
/// when there is one).
///
/// {@category protocol}
final class const PathKey(
  /// The key.
  final String name,
) extends PathSegment {
  /// Creates a key step.
  this;

  @override
  bool operator ==(Object other) => other is PathKey && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}

/// An index of an array, from 0.
///
/// {@category protocol}
final class const PathIndex(
  /// The index.
  final int index,
) extends PathSegment {
  /// Creates an index step; [index] is not negative.
  this : assert(index >= 0, 'index is not negative');

  @override
  bool operator ==(Object other) => other is PathIndex && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => '$index';
}
