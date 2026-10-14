import 'child_reader.dart';
import 'name.dart';
import 'node.dart';
import 'value.dart';

/// One field of an [ObjectValue], `name: value` (spec §2.9.8).
final class const ObjectField(
  /// The field name.
  final Name name,

  /// The field value.
  final Value value, {
  super.start,
  super.end,
}) extends Node {
  /// Creates an object field.
  this;

  @override
  List<Node> get children => [name, value];

  @override
  ObjectField rebuildFrom(ChildReader read) =>
      ObjectField(read.one(), read.one(), start: start, end: end);
}
