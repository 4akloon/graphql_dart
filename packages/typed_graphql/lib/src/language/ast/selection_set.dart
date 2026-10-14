import 'child_reader.dart';
import 'node.dart';
import 'selection.dart';

/// A selection set, `{ selections }` (spec §2.4).
///
/// It is empty only when the parser allows empty selection sets (a
/// working-draft option).
final class SelectionSet(
  List<Selection> selections, {
  super.start,
  super.end,
}) extends Node {
  /// Creates a selection set.
  this;

  /// The selections, in source order.
  final List<Selection> selections = List.unmodifiable(selections);

  @override
  List<Node> get children => selections;

  @override
  SelectionSet rebuildFrom(ChildReader read) =>
      SelectionSet(read.all(), start: start, end: end);
}
