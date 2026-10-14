import 'child_reader.dart';
import 'name.dart';
import 'node.dart';
import 'value.dart';

/// An argument of a field or directive, `name: value` (spec §2.6).
final class const Argument(
  /// The argument name.
  final Name name,

  /// The argument value.
  final Value value, {
  super.start,
  super.end,
}) extends Node {
  /// Creates an argument.
  this;

  @override
  List<Node> get children => [name, value];

  @override
  Argument rebuildFrom(ChildReader read) =>
      Argument(read.one(), read.one(), start: start, end: end);
}
