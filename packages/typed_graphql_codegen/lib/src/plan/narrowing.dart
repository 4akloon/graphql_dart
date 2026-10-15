import 'condition.dart';
import 'selection_source.dart';

/// A type condition that narrows an abstract parent: only the types it
/// reaches matter to the planner.
final class const Narrowing(
  /// The name of the type condition.
  final String typeCondition, {

  /// The inline fragment's selection set, with the inherited and own
  /// conditions; null for a fragment spread.
  final SelectionSource? source,

  /// The spread fragment's name; null for an inline fragment.
  final String? fragmentName,

  /// The conditions a fragment spread sits under.
  final List<Condition> conditions = const [],
}) {
  /// Creates a narrowing.
  this;
}
