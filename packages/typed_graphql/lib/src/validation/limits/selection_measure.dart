import 'dart:math';

import '../../language/ast/executable_definition.dart';
import '../../language/ast/selection.dart';
import '../validation_context.dart';
import 'measured_quantity.dart';

/// Measures one [MeasuredQuantity] of operations with their fragments
/// expanded, in time linear in the document (R3.5).
///
/// A fragment's value is computed once and reused by every spread, so a
/// chain of fragments that expands exponentially costs one visit each.
/// The walk uses an explicit stack. A fragment on the stack when it is
/// spread again is a cycle (`NoFragmentCyclesRule` reports it) and counts
/// 0, like an unknown fragment. Counts saturate at one over the [limit]:
/// they cannot overflow and an excess is all a rule needs.
final class SelectionMeasure(
  final ValidationContext context,
  final MeasuredQuantity quantity,

  /// The most the rule allows.
  final int limit,
) {
  /// Creates a measure of [quantity] for a rule with [limit].
  this;

  final Map<String, int> _fragmentValues = {};

  int? get _cap => quantity.isAdditive ? limit + 1 : null;

  /// The value of [operation], or null once the context's step budget is
  /// spent.
  int? measure(OperationDefinition operation) => measureSelections(
    operation.selectionSet.selections,
    own: quantity.ofOperation(operation),
  );

  /// The value of [selections], fragments expanded, plus [own], or null once
  /// the context's step budget is spent.
  ///
  /// Fragment values are memoised for the life of the measure, so asking
  /// for the selections of many fields still visits each fragment once.
  int? measureSelections(List<Selection> selections, {int own = 0}) {
    final inProgress = <String>{};
    final stack = [_Frame(selections, own)];
    while (true) {
      final frame = stack.last;
      if (frame.index < frame.selections.length) {
        if (!context.spend(1)) {
          return null;
        }
        final child = _visit(
          frame.selections[frame.index++],
          frame,
          inProgress,
        );
        if (child != null) {
          stack.add(child);
        }
        continue;
      }
      stack.removeLast();
      final value = _add(frame.own, frame.accumulated);
      if (frame.fragmentName case final name?) {
        inProgress.remove(name);
        _fragmentValues[name] = value;
      }
      final passed = _add(frame.spreadOwn, value);
      if (stack.isEmpty) {
        return passed;
      }
      _fold(stack.last, passed);
    }
  }

  // Folds the value of [selection] into [frame] when it is known, else
  // returns the frame that computes it.
  _Frame? _visit(Selection selection, _Frame frame, Set<String> inProgress) {
    final own = quantity.ofSelection(selection);
    switch (selection) {
      case Field(selectionSet: null):
        _fold(frame, own);
      case Field(:final selectionSet?) || InlineFragment(:final selectionSet):
        return _Frame(selectionSet.selections, own);
      case FragmentSpread(:final name):
        final fragment = context.fragmentNamed(name.value);
        final known = _fragmentValues[name.value];
        if (known != null) {
          _fold(frame, _add(own, known));
        } else if (fragment == null || inProgress.contains(name.value)) {
          _fold(frame, own);
        } else {
          inProgress.add(name.value);
          return _Frame(
            fragment.selectionSet.selections,
            quantity.ofFragment(fragment),
            fragmentName: name.value,
            spreadOwn: own,
          );
        }
    }
    return null;
  }

  void _fold(_Frame frame, int value) {
    frame.accumulated = quantity.isAdditive
        ? _add(frame.accumulated, value)
        : max(frame.accumulated, value);
  }

  int _add(int first, int second) {
    final sum = first + second;
    return switch (_cap) {
      final cap? => min(sum, cap),
      null => sum,
    };
  }
}

final class _Frame(
  final List<Selection> selections,
  final int own, {
  final String? fragmentName,
  final int spreadOwn = 0,
}) {
  this;

  int index = 0;
  int accumulated = 0;
}
