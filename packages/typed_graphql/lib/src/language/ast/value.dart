import 'child_reader.dart';
import 'name.dart';
import 'node.dart';
import 'object_field.dart';

/// An input value as written in a document (spec §2.9).
sealed class const Value({super.start, super.end}) extends Node {
  /// Creates a value spanning `start` to `end`.
  this;
}

/// A variable, `$name` (spec §2.10).
final class const Variable(
  /// The name without the `$`.
  final Name name, {
  super.start,
  super.end,
}) extends Value {
  /// Creates a variable.
  this;

  @override
  List<Node> get children => [name];

  @override
  Variable rebuildFrom(ChildReader read) =>
      Variable(read.one(), start: start, end: end);
}

/// An integer, kept as written so no precision is lost (spec §2.9.1).
final class const IntValue(
  /// The lexeme, such as `-12`.
  final String value, {
  super.start,
  super.end,
}) extends Value {
  /// Creates an integer value.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value];

  @override
  IntValue rebuildFrom(ChildReader read) => this;
}

/// A float, kept as written so no precision is lost (spec §2.9.2).
final class const FloatValue(
  /// The lexeme, such as `1.5e-3`.
  final String value, {
  super.start,
  super.end,
}) extends Value {
  /// Creates a float value.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value];

  @override
  FloatValue rebuildFrom(ChildReader read) => this;
}

/// A string or block string; also a description (spec §2.9.4).
final class const StringValue(
  /// The decoded value: escapes resolved, block indentation removed.
  final String value, {

  /// Whether it was written as a block string, `"""..."""`.
  final bool isBlock = false,
  super.start,
  super.end,
}) extends Value {
  /// Creates a string value.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value, isBlock];

  @override
  StringValue rebuildFrom(ChildReader read) => this;
}

/// `true` or `false` (spec §2.9.3).
final class const BooleanValue(
  /// The value.
  final bool value, {
  super.start,
  super.end,
}) extends Value {
  /// Creates a boolean value.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value];

  @override
  BooleanValue rebuildFrom(ChildReader read) => this;
}

/// `null` (spec §2.9.5).
final class const NullValue({super.start, super.end}) extends Value {
  /// Creates a null value.
  this;

  @override
  List<Node> get children => const [];

  @override
  NullValue rebuildFrom(ChildReader read) => this;
}

/// An enum value: a name other than `true`, `false` and `null` (spec
/// §2.9.6).
final class const EnumValue(
  /// The name as written.
  final String value, {
  super.start,
  super.end,
}) extends Value {
  /// Creates an enum value.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value];

  @override
  EnumValue rebuildFrom(ChildReader read) => this;
}

/// A list, `[a, b]` (spec §2.9.7).
final class ListValue(
  List<Value> values, {
  super.start,
  super.end,
}) extends Value {
  /// Creates a list value.
  this;

  /// The items, in order.
  final List<Value> values = List.unmodifiable(values);

  @override
  List<Node> get children => values;

  @override
  ListValue rebuildFrom(ChildReader read) =>
      ListValue(read.all(), start: start, end: end);
}

/// An input object, `{a: 1}` (spec §2.9.8).
final class ObjectValue(
  List<ObjectField> fields, {
  super.start,
  super.end,
}) extends Value {
  /// Creates an object value.
  this;

  /// The fields, in source order; a name may repeat (validation reports
  /// it).
  final List<ObjectField> fields = List.unmodifiable(fields);

  @override
  List<Node> get children => fields;

  @override
  ObjectValue rebuildFrom(ChildReader read) =>
      ObjectValue(read.all(), start: start, end: end);
}
