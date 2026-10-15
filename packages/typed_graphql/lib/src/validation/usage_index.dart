import '../language/ast/document.dart';
import '../language/ast/executable_definition.dart';
import '../language/ast/node.dart';
import '../language/ast/selection.dart';
import '../language/ast/value.dart';
import '../language/ast/variable_definition.dart';
import '../language/visitor/ast_visitor.dart';
import '../language/visitor/visit_action.dart';
import 'fragment_spread_collector.dart';
import 'type_info.dart';
import 'variable_usage.dart';

/// The variable usages of each executable definition, recorded during the
/// one walk of a run, and the closures of operations over them and over the
/// fragments they spread.
///
/// graphql-js walks each fragment again when a rule asks for an
/// operation's variables; recording them in the walk does the same work
/// once. The queries need the whole document, so they answer only after
/// the walk left it.
final class UsageIndex extends AstVisitor {
  /// Records usages with the input types of [typeInfo]; [spend] charges
  /// the closures to the run's step budget and says whether it lasts.
  UsageIndex(this._typeInfo, this._spend, this._fragmentNamed);

  final TypeInfo _typeInfo;
  final bool Function(int steps) _spend;
  final FragmentDefinition? Function(String name) _fragmentNamed;

  // Keyed by node identity: syntax nodes do not override ==.
  final Map<ExecutableDefinition, List<VariableUsage>> _usages = {};
  final Map<ExecutableDefinition, List<FragmentSpread>> _spreads = {};
  final Map<OperationDefinition, List<FragmentDefinition>> _fragments = {};
  final Map<OperationDefinition, List<VariableUsage>> _closures = {};
  List<VariableUsage>? _currentUsages;
  bool _isComplete = false;

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case final ExecutableDefinition definition:
        _currentUsages = _usages[definition] = [];
      // The variable a definition declares is not a usage.
      case VariableDefinition():
        return VisitAction.skip;
      case final Variable variable:
        _currentUsages?.add(
          VariableUsage(
            variable,
            _typeInfo.inputType,
            parentType: _typeInfo.parentInputType,
            defaultValue: _typeInfo.defaultValue,
          ),
        );
      case _:
        break;
    }
    return VisitAction.next;
  }

  @override
  void leave(Node node) {
    switch (node) {
      case ExecutableDefinition():
        _currentUsages = null;
      case Document():
        _isComplete = true;
      case _:
        break;
    }
  }

  /// The usages directly in [definition], in document order.
  List<VariableUsage> variableUsagesOf(ExecutableDefinition definition) {
    _checkComplete();
    return _usages[definition] ?? const [];
  }

  /// The fragments [operation] spreads, directly or through other
  /// fragments, each once, in graphql-js's order.
  List<FragmentDefinition> recursivelyReferencedFragments(
    OperationDefinition operation,
  ) {
    _checkComplete();
    return _fragments[operation] ??= _collectFragments(operation);
  }

  /// The usages in [operation] and in every fragment it reaches.
  List<VariableUsage> recursiveVariableUsages(OperationDefinition operation) {
    _checkComplete();
    return _closures[operation] ??= [
      ...variableUsagesOf(operation),
      for (final fragment in recursivelyReferencedFragments(operation))
        if (_spend(variableUsagesOf(fragment).length + 1))
          ...variableUsagesOf(fragment),
    ];
  }

  List<FragmentDefinition> _collectFragments(OperationDefinition operation) {
    final fragments = <FragmentDefinition>[];
    final names = <String>{};
    final pending = <ExecutableDefinition>[operation];
    while (pending.isNotEmpty) {
      final spreads = _spreadsOf(pending.removeLast());
      if (!_spend(spreads.length + 1)) {
        break;
      }
      for (final spread in spreads) {
        final fragment = _fragmentNamed(spread.name.value);
        if (names.add(spread.name.value) && fragment != null) {
          fragments.add(fragment);
          pending.add(fragment);
        }
      }
    }
    return fragments;
  }

  // In graphql-js's order (getRecursivelyReferencedFragments): the spreads
  // of a selection set, then those of its nested sets, last first.
  List<FragmentSpread> _spreadsOf(ExecutableDefinition definition) =>
      _spreads[definition] ??= const FragmentSpreadCollector().collect(
        switch (definition) {
          OperationDefinition(:final selectionSet) => selectionSet,
          FragmentDefinition(:final selectionSet) => selectionSet,
        },
      );

  void _checkComplete() {
    if (!_isComplete) {
      throw StateError('The document has not been walked to its end.');
    }
  }
}
