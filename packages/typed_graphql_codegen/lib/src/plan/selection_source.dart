import 'package:typed_graphql/typed_graphql.dart';

import 'condition.dart';

/// A selection set to collect, with the variable conditions it sits under.
final class const SelectionSource(
  /// The selection set.
  final SelectionSet selectionSet, {

  /// Whether a variable `@include` or `@skip` on an enclosing inline
  /// fragment or field makes everything in the set conditional.
  final bool isConditional = false,

  /// Those conditions, which a fragment spread in the set inherits.
  final List<Condition> conditions = const [],
}) {
  /// Creates a source.
  this;
}
