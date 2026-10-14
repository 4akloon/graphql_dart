import 'child_reader.dart';
import 'name.dart';
import 'node.dart';

/// A reference to a type: named, list or non-null (spec §2.11).
///
/// {@category language}
sealed class const TypeRef({super.start, super.end}) extends Node {
  /// Creates a type reference spanning `start` to `end`.
  this;
}

/// A type by its name, `Name`.
///
/// {@category language}
final class const NamedType(
  /// The type's name.
  final Name name, {
  super.start,
  super.end,
}) extends TypeRef {
  /// Creates a named type.
  this;

  @override
  List<Node> get children => [name];

  @override
  NamedType rebuildFrom(ChildReader read) =>
      NamedType(read.one(), start: start, end: end);
}

/// A list type, `[Type]`.
///
/// {@category language}
final class const ListType(
  /// The type of the items.
  final TypeRef type, {
  super.start,
  super.end,
}) extends TypeRef {
  /// Creates a list type.
  this;

  @override
  List<Node> get children => [type];

  @override
  ListType rebuildFrom(ChildReader read) =>
      ListType(read.one(), start: start, end: end);
}

/// A non-null type, `Type!`; it wraps a named or list type, never another
/// non-null type.
///
/// {@category language}
final class const NonNullType(
  /// The wrapped type.
  final TypeRef type, {
  super.start,
  super.end,
}) extends TypeRef {
  /// Creates a non-null type; [type] must not be a [NonNullType].
  this : assert(type is! NonNullType, 'a non-null type is not wrapped twice');

  @override
  List<Node> get children => [type];

  @override
  NonNullType rebuildFrom(ChildReader read) {
    final wrapped = read.one<TypeRef>();
    if (wrapped is NonNullType) {
      throw StateError('a non-null type is not wrapped twice');
    }
    return NonNullType(wrapped, start: start, end: end);
  }
}
