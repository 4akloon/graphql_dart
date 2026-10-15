import 'package:typed_graphql/typed_graphql.dart';

import 'applicability.dart';
import 'field_collector.dart';
import 'selection_source.dart';

/// Finds out whether the top level of an operation spreads a fragment that
/// plans as a sealed class (R7.9): the class reads the type of the root
/// object, so the document selects `__typename` there, which a subscription's
/// root cannot.
///
/// The root is an object type, so an inline fragment, or a fragment on an
/// abstract type without narrowing inside, flattens into the root class and
/// needs nothing.
final class RootTypename {
  /// Creates the finder for [schema]; [fragments] are the project's fragment
  /// definitions by name.
  const RootTypename(this.schema, this.fragments);

  /// The schema, which tells abstract types from object types.
  final Schema schema;

  /// The project's fragment definitions, by name.
  final Map<String, FragmentDefinition> fragments;

  /// Whether the top level of [root] spreads a sealed fragment.
  bool isNeededBy(SelectionSet root) => find(root) != null;

  /// The first top-level selection of [root] that leads, through inline
  /// fragments and spread fragments, to a fragment that plans as a sealed
  /// class, with that fragment's name and its abstract type's name; null when
  /// none does.
  ({Node selection, String typeName, String fragmentName})? find(
    SelectionSet root,
  ) {
    final visited = <String>{};
    for (final top in root.selections) {
      final found = _search(top, visited);
      if (found != null) {
        return (
          selection: top,
          typeName: found.typeName,
          fragmentName: found.fragmentName,
        );
      }
    }
    return null;
  }

  // The sealed fragment [top] reaches; [visited] holds the fragments already
  // searched in vain.
  ({String typeName, String fragmentName})? _search(
    Selection top,
    Set<String> visited,
  ) {
    final pending = <Selection>[top];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case Field():
          continue;
        case InlineFragment(:final selectionSet):
          pending.addAll(selectionSet.selections);
        case FragmentSpread(:final name):
          final FragmentDefinition? fragment = fragments[name.value];
          if (fragment == null || !visited.add(name.value)) continue;
          if (_isSealed(fragment)) {
            return (
              typeName: fragment.typeCondition.name.value,
              fragmentName: name.value,
            );
          }
          pending.addAll(fragment.selectionSet.selections);
      }
    }
    return null;
  }

  // Whether the planner makes [fragment] a sealed class: its type is
  // abstract and a narrowing inside reaches an object type.
  bool _isSealed(FragmentDefinition fragment) {
    final SchemaType? type = schema.typeNamed(
      fragment.typeCondition.name.value,
    );
    if (type == null) return false;
    final collected = FieldCollector(
      schema,
      fragments,
    ).collect(type, [SelectionSource(fragment.selectionSet)]);
    return Applicability(schema)
        .reachedBy(type, collected.narrowings)
        .isNotEmpty;
  }
}
