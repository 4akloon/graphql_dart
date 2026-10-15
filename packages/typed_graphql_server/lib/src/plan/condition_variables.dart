import 'package:typed_graphql/typed_graphql.dart';

/// Finds the variables that decide which fields an operation collects: the
/// ones written as the `if` argument of `@skip`, `@include` or `@defer` in
/// the operation or in a fragment it can reach (R4.8).
final class ConditionVariables {
  /// Searches without state.
  const ConditionVariables();

  static const Set<String> _directives = {'skip', 'include', 'defer'};

  /// The names (without `$`) in order of discovery, each once. Selections
  /// are walked with an explicit stack and each fragment once, so a document
  /// of any shape costs time linear in its size.
  List<String> find(
    OperationDefinition operation,
    Map<String, FragmentDefinition> fragments,
  ) {
    final names = <String>{};
    final visitedFragments = <String>{};
    final pending = <SelectionSet>[operation.selectionSet];
    while (pending.isNotEmpty) {
      for (final selection in pending.removeLast().selections) {
        _addNames(selection, names);
        final next = _nested(selection, fragments, visitedFragments);
        if (next != null) {
          pending.add(next);
        }
      }
    }
    return List.unmodifiable(names);
  }

  // The selection set to walk next inside [selection]; a fragment only the
  // first time it is spread.
  SelectionSet? _nested(
    Selection selection,
    Map<String, FragmentDefinition> fragments,
    Set<String> visitedFragments,
  ) => switch (selection) {
    Field(:final selectionSet) => selectionSet,
    InlineFragment(:final selectionSet) => selectionSet,
    FragmentSpread(name: Name(:final value)) =>
      visitedFragments.add(value) ? fragments[value]?.selectionSet : null,
  };

  void _addNames(Selection selection, Set<String> names) {
    final directives = switch (selection) {
      Field(:final directives) => directives,
      InlineFragment(:final directives) => directives,
      FragmentSpread(:final directives) => directives,
    };
    for (final directive in directives) {
      if (!_directives.contains(directive.name.value)) {
        continue;
      }
      for (final argument in directive.arguments) {
        if (argument.name.value == 'if' && argument.value is Variable) {
          names.add((argument.value as Variable).name.value);
        }
      }
    }
  }
}
