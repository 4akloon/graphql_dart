import 'package:typed_graphql/typed_graphql.dart';

/// Finds out whether the top level of an operation reads an abstract type
/// (R7.9): then the document selects `__typename` there, which a
/// subscription's root cannot.
final class RootTypename {
  /// Creates the finder for [schema]; [fragmentNamed] looks a fragment
  /// definition up by name.
  const RootTypename(this.schema, this.fragmentNamed);

  /// The schema, which tells abstract types from object types.
  final Schema schema;

  /// The project's fragment definitions by name.
  final FragmentDefinition? Function(String name) fragmentNamed;

  /// Whether the top level of [root] reads an abstract type.
  bool isNeededBy(SelectionSet root) => find(root) != null;

  /// The first top-level selection of [root] that reads an abstract type,
  /// through spread fragments too, with the abstract type's name and, when a
  /// fragment definition is on it, the fragment's name; null when none does.
  ({Node selection, String typeName, String? fragmentName})? find(
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

  // The abstract type [top] reads, through spread fragments; [visited] holds
  // the fragments already searched in vain.
  ({String typeName, String? fragmentName})? _search(
    Selection top,
    Set<String> visited,
  ) {
    final pending = <Selection>[top];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case Field():
          continue;
        case InlineFragment(:final typeCondition, :final selectionSet):
          final String? typeName = typeCondition?.name.value;
          if (typeName != null && _isAbstract(typeName)) {
            return (typeName: typeName, fragmentName: null);
          }
          pending.addAll(selectionSet.selections);
        case FragmentSpread(:final name):
          final FragmentDefinition? fragment = fragmentNamed(name.value);
          if (fragment == null || !visited.add(name.value)) continue;
          final String typeName = fragment.typeCondition.name.value;
          if (_isAbstract(typeName)) {
            return (typeName: typeName, fragmentName: name.value);
          }
          pending.addAll(fragment.selectionSet.selections);
      }
    }
    return null;
  }

  bool _isAbstract(String typeName) => switch (schema.typeNamed(typeName)) {
    InterfaceType() || UnionType() => true,
    _ => false,
  };
}
