import '../../language/ast/executable_definition.dart';
import '../fragment_spread_collector.dart';
import '../validation_context.dart';
import 'strongly_connected_components.dart';

/// The fragments that are on a cycle of spreads.
///
/// A fragment on the path of the merge is skipped to end a recursive
/// fragment, but only these can be skipped rightly: a fragment on no cycle
/// cannot be spread inside what it contains, so it can only be on the path
/// as a sibling of the field being merged. Skipping it would hide the same
/// fragment spread beside a field (spec §5.3.2), and so would skipping a
/// fragment that merely reaches a cycle.
///
/// Found as the strongly connected components of the spread graph
/// ([StronglyConnectedComponents]) with two or more fragments, or with a
/// fragment that spreads itself. Linear in the spreads, each charged to the
/// step budget.
final class CyclicFragments {
  /// Finds the fragments of [context]'s document that are on a cycle.
  CyclicFragments(ValidationContext context) : names = _find(context);

  /// The names of the fragments that are on a cycle.
  final Set<String> names;

  static Set<String> _find(ValidationContext context) {
    final edges = <String, Set<String>>{};
    for (final definition in context.document.definitions) {
      if (definition is! FragmentDefinition) continue;
      final name = definition.name.value;
      if (!identical(context.fragmentNamed(name), definition)) continue;
      final spreads = const FragmentSpreadCollector().collect(
        definition.selectionSet,
      );
      if (!context.spend(spreads.length + 1)) break;
      edges[name] = {
        for (final spread in spreads) spread.name.value,
      };
    }
    // Spreads of unknown fragments lead nowhere.
    for (final targets in edges.values) {
      targets.retainWhere(edges.containsKey);
    }
    return StronglyConnectedComponents(edges).cyclicNodes();
  }
}
