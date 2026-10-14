import '../language/ast/selection.dart';
import '../language/ast/selection_set.dart';

/// Finds the fragment spreads in a selection set, as graphql-js's
/// `getFragmentSpreads`: nested selections included, other fragments'
/// bodies not, in graphql-js's order (the message of a cycle depends on
/// it).
final class const FragmentSpreadCollector() {
  /// Creates the collector.
  this;

  /// The spreads inside [root], found with an explicit stack.
  List<FragmentSpread> collect(SelectionSet root) {
    final spreads = <FragmentSpread>[];
    final pending = [root];
    while (pending.isNotEmpty) {
      for (final selection in pending.removeLast().selections) {
        switch (selection) {
          case final FragmentSpread spread:
            spreads.add(spread);
          case Field(:final selectionSet?):
            pending.add(selectionSet);
          case InlineFragment(:final selectionSet):
            pending.add(selectionSet);
          case Field():
            break;
        }
      }
    }
    return spreads;
  }
}
