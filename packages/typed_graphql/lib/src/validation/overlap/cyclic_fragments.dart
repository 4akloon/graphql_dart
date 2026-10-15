import '../../language/ast/executable_definition.dart';
import '../fragment_spread_collector.dart';
import '../validation_context.dart';

/// The fragments that are on a cycle of spreads or reach one.
///
/// A fragment on the path of the merge is skipped to end a recursive
/// fragment, but only these can be skipped rightly: a fragment that
/// reaches no cycle cannot be spread inside what it contains. Skipping any
/// other would hide the same fragment spread beside a field (spec §5.3.2).
///
/// Found as Kahn's algorithm does: fragments whose spreads all lead to
/// fragments already removed are removed in turn; those left may reach a
/// cycle. Linear in the spreads, each charged to the step budget.
final class CyclicFragments {
  /// Finds the fragments of [context]'s document that may be on a cycle.
  CyclicFragments(ValidationContext context) : names = _find(context);

  /// The names of the fragments that are on a cycle or reach one.
  final Set<String> names;

  static Set<String> _find(ValidationContext context) {
    final unresolved = <String, int>{};
    final referrers = <String, List<String>>{};
    for (final definition in context.document.definitions) {
      if (definition is! FragmentDefinition) continue;
      final name = definition.name.value;
      if (!identical(context.fragmentNamed(name), definition)) continue;
      final spreads = const FragmentSpreadCollector().collect(
        definition.selectionSet,
      );
      if (!context.spend(spreads.length + 1)) break;
      final targets = {
        for (final spread in spreads)
          if (context.fragmentNamed(spread.name.value) != null)
            spread.name.value,
      };
      unresolved[name] = targets.length;
      for (final target in targets) {
        (referrers[target] ??= []).add(name);
      }
    }
    final ready = [
      for (final MapEntry(:key, :value) in unresolved.entries)
        if (value == 0) key,
    ];
    while (ready.isNotEmpty) {
      for (final referrer
          in referrers[ready.removeLast()] ?? const <String>[]) {
        if (unresolved.update(referrer, (count) => count - 1) == 0) {
          ready.add(referrer);
        }
      }
    }
    return {
      for (final MapEntry(:key, :value) in unresolved.entries)
        if (value > 0) key,
    };
  }
}
