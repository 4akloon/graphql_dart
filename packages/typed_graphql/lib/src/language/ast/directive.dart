import 'argument.dart';
import 'child_reader.dart';
import 'name.dart';
import 'node.dart';

/// A directive applied to a node, `@name(arguments)` (spec §2.12).
///
/// {@category language}
final class Directive(
  /// The directive name, without the `@`.
  final Name name, {
  List<Argument> arguments = const [],
  super.start,
  super.end,
}) extends Node {
  /// Creates a directive.
  this;

  /// The arguments, in source order.
  final List<Argument> arguments = List.unmodifiable(arguments);

  @override
  List<Node> get children => [name, ...arguments];

  @override
  Directive rebuildFrom(ChildReader read) =>
      Directive(read.one(), arguments: read.all(), start: start, end: end);
}
