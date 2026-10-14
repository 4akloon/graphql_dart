import '../../language/ast/executable_definition.dart';
import '../../language/ast/selection.dart';

/// What a limit rule counts in an operation, and how a node contributes to
/// it (R3.5).
///
/// A node's value is its own contribution plus the combination of its
/// children's values: the sum for a count, the maximum for the depth.
enum MeasuredQuantity {
  /// The nesting of fields; a field adds one level, fragments none.
  depth,

  /// The fields written with an alias.
  aliases,

  /// The directives, wherever they are applied.
  directives,

  /// The fields named `fields`, `interfaces`, `possibleTypes` or
  /// `inputFields` on a path, as graphql-js's `MaxIntrospectionDepthRule`
  /// counts them.
  introspectionLists;

  static const Set<String> _listFieldNames = {
    'fields',
    'interfaces',
    'possibleTypes',
    'inputFields',
  };

  /// Whether children combine by sum (a count) rather than by maximum.
  bool get isAdditive => this == aliases || this == directives;

  /// What [selection] adds, not counting what it contains.
  int ofSelection(Selection selection) => switch (this) {
    depth => selection is Field ? 1 : 0,
    introspectionLists =>
      selection is Field && _listFieldNames.contains(selection.name.value)
          ? 1
          : 0,
    aliases => selection is Field && selection.alias != null ? 1 : 0,
    directives => switch (selection) {
      Field(directives: final applied) ||
      FragmentSpread(directives: final applied) ||
      InlineFragment(directives: final applied) => applied.length,
    },
  };

  /// What a spread of [fragment] adds besides its selections: the
  /// directives on its definition.
  int ofFragment(FragmentDefinition fragment) =>
      this == directives ? fragment.directives.length : 0;

  /// What [operation] adds besides its selections: its directives and
  /// those of its variable definitions.
  int ofOperation(OperationDefinition operation) {
    if (this != directives) {
      return 0;
    }
    var total = operation.directives.length;
    for (final definition in operation.variableDefinitions) {
      total += definition.directives.length;
    }
    return total;
  }
}
