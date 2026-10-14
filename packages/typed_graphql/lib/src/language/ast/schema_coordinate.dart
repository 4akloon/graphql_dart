import 'child_reader.dart';
import 'name.dart';
import 'node.dart';

/// A schema coordinate: the text that names one element of a schema, such
/// as `Query.hero(episode:)` (September2025 §2 "Schema Coordinates").
///
/// The field names follow graphql-js's nodes. A coordinate is parsed with
/// [Parser.parseSchemaCoordinate]; resolving it against a schema is not the
/// parser's work.
sealed class const SchemaCoordinate(
  /// The type or, after `@`, the directive the coordinate starts from.
  final Name name, {
  super.start,
  super.end,
}) extends Node {
  /// Creates a coordinate spanning [start] to [end].
  this;
}

/// A type, `Name`.
final class const TypeCoordinate(
  super.name, {
  super.start,
  super.end,
}) extends SchemaCoordinate {
  /// Creates a type coordinate.
  this;

  @override
  List<Node> get children => [name];

  @override
  TypeCoordinate rebuildFrom(ChildReader read) =>
      TypeCoordinate(read.one(), start: start, end: end);
}

/// A field, input field or enum value of a type, `Name.Name`.
final class const MemberCoordinate(
  super.name,

  /// The name of the field, input field or enum value.
  final Name memberName, {
  super.start,
  super.end,
}) extends SchemaCoordinate {
  /// Creates a member coordinate.
  this;

  @override
  List<Node> get children => [name, memberName];

  @override
  MemberCoordinate rebuildFrom(ChildReader read) =>
      MemberCoordinate(read.one(), read.one(), start: start, end: end);
}

/// An argument of a field, `Name.Name(Name:)`.
final class const ArgumentCoordinate(
  super.name,

  /// The name of the field.
  final Name fieldName,

  /// The name of the argument.
  final Name argumentName, {
  super.start,
  super.end,
}) extends SchemaCoordinate {
  /// Creates an argument coordinate.
  this;

  @override
  List<Node> get children => [name, fieldName, argumentName];

  @override
  ArgumentCoordinate rebuildFrom(ChildReader read) => ArgumentCoordinate(
    read.one(),
    read.one(),
    read.one(),
    start: start,
    end: end,
  );
}

/// A directive, `@Name`.
final class const DirectiveCoordinate(
  super.name, {
  super.start,
  super.end,
}) extends SchemaCoordinate {
  /// Creates a directive coordinate.
  this;

  @override
  List<Node> get children => [name];

  @override
  DirectiveCoordinate rebuildFrom(ChildReader read) =>
      DirectiveCoordinate(read.one(), start: start, end: end);
}

/// An argument of a directive, `@Name(Name:)`.
final class const DirectiveArgumentCoordinate(
  super.name,

  /// The name of the argument.
  final Name argumentName, {
  super.start,
  super.end,
}) extends SchemaCoordinate {
  /// Creates a directive argument coordinate.
  this;

  @override
  List<Node> get children => [name, argumentName];

  @override
  DirectiveArgumentCoordinate rebuildFrom(ChildReader read) =>
      DirectiveArgumentCoordinate(
        read.one(),
        read.one(),
        start: start,
        end: end,
      );
}
