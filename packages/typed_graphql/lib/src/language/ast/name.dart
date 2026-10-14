import 'child_reader.dart';
import 'node.dart';

/// A name, such as a field, type or argument name (spec §2.1.9).
final class const Name(
  /// The name as written: `[_A-Za-z][_0-9A-Za-z]*`.
  final String value, {
  super.start,
  super.end,
}) extends Node {
  /// Creates a name.
  this;

  @override
  List<Node> get children => const [];

  @override
  List<Object?> get scalars => [value];

  @override
  Name rebuildFrom(ChildReader read) => this;
}
