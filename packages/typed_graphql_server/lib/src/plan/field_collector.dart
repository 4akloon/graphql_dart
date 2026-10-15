import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_problem.dart';
import '../coercion/coercion_result.dart';
import 'field_accumulator.dart';
import 'plan_context.dart';
import 'plan_node.dart';

/// September2025 section 6.3.2 `CollectFields` and `CollectSubfields`, with
/// graphql-js 17's `collectFieldsImpl` rules for `@skip`, `@include`, type
/// conditions and fragments (R4.8).
///
/// Selections are walked with an explicit stack, so a deeply nested document
/// cannot overflow it, and each fragment is expanded once per collection (a
/// repeat adds the same fields again), so a chain of fragments that each
/// spread the next one twice costs time linear in the document.
final class FieldCollector {
  /// Collects in [context].
  FieldCollector(this.context);

  /// What collection reads.
  final PlanContext context;

  /// Collects the fields of [selectionSets] for [runtimeType] into a node.
  /// Several sets share one run, as the field nodes of one response key do.
  PlanNode collect(
    ObjectType runtimeType,
    Iterable<SelectionSet> selectionSets,
  ) {
    final groups = <String, FieldAccumulator>{};
    final visitedFragments = <String, bool>{};
    for (final selectionSet in selectionSets) {
      final problem = _walk(
        runtimeType,
        selectionSet,
        groups,
        visitedFragments,
      );
      if (problem != null) {
        return PlanNode(runtimeType, const [], problem: problem);
      }
    }
    return PlanNode(runtimeType, [
      for (final group in groups.values)
        if (group.isDefinedOn(context, runtimeType))
          group.build(context, runtimeType),
    ]);
  }

  CoercionProblem? _walk(
    ObjectType runtimeType,
    SelectionSet root,
    Map<String, FieldAccumulator> groups,
    Map<String, bool> visitedFragments,
  ) {
    final stack = [_Frame(root.selections, isDeferred: false)];
    while (stack.isNotEmpty) {
      final frame = stack.last;
      if (frame.isFinished) {
        stack.removeLast();
        continue;
      }
      final step = _visit(
        frame.next(),
        frame.isDeferred,
        runtimeType,
        groups,
        visitedFragments,
      );
      switch (step) {
        case _Descend(:final frame):
          stack.add(frame);
        case _Failed(:final problem):
          return problem;
        case _Done():
          break;
      }
    }
    return null;
  }

  _Step _visit(
    Selection selection,
    bool isDeferred,
    ObjectType runtimeType,
    Map<String, FieldAccumulator> groups,
    Map<String, bool> visitedFragments,
  ) {
    final directives = switch (selection) {
      Field(:final directives) => directives,
      InlineFragment(:final directives) => directives,
      FragmentSpread(:final directives) => directives,
    };
    switch (context.conditionals.isIncluded(
      directives,
      context.conditionValues,
    )) {
      case CoercionSuccess(value: false):
        return const _Done();
      case CoercionFailure(:final problems):
        return _Failed(problems.first);
      case CoercionSuccess():
        break;
    }
    return switch (selection) {
      final Field field => _addField(field, isDeferred, groups),
      final InlineFragment fragment => _enterInline(
        fragment,
        isDeferred,
        runtimeType,
      ),
      final FragmentSpread spread => _enterSpread(
        spread,
        isDeferred,
        runtimeType,
        visitedFragments,
      ),
    };
  }

  _Step _addField(
    Field field,
    bool isDeferred,
    Map<String, FieldAccumulator> groups,
  ) {
    final key = field.alias?.value ?? field.name.value;
    final group = groups[key];
    if (group == null) {
      groups[key] = FieldAccumulator(field, isDeferred: isDeferred);
    } else {
      group.add(field, isDeferred: isDeferred);
    }
    return const _Done();
  }

  _Step _enterInline(
    InlineFragment fragment,
    bool isDeferred,
    ObjectType runtimeType,
  ) {
    if (!_matches(fragment.typeCondition, runtimeType)) {
      return const _Done();
    }
    return switch (context.defers.isDeferred(
      fragment.directives,
      context.conditionValues,
    )) {
      CoercionSuccess(:final value) => _Descend(
        _Frame(
          fragment.selectionSet.selections,
          isDeferred: isDeferred || value == true,
        ),
      ),
      final CoercionFailure failure => _Failed(failure.problems.first),
    };
  }

  _Step _enterSpread(
    FragmentSpread spread,
    bool isDeferred,
    ObjectType runtimeType,
    Map<String, bool> visitedFragments,
  ) {
    final name = spread.name.value;
    final fragment = context.fragments[name];
    if (fragment == null || !_matches(fragment.typeCondition, runtimeType)) {
      return const _Done();
    }
    switch (context.defers.isDeferred(
      spread.directives,
      context.conditionValues,
    )) {
      case CoercionSuccess(value: final bool isNewlyDeferred):
        // graphql-js: a deferred spread is skipped once the fragment was
        // visited at all; a plain one is skipped once visited plainly, and
        // a plain visit after a deferred one expands it again.
        final visitedAsDeferred = visitedFragments[name];
        if (isNewlyDeferred
            ? visitedAsDeferred != null
            : visitedAsDeferred == false) {
          return const _Done();
        }
        visitedFragments[name] = isNewlyDeferred;
        return _Descend(
          _Frame(
            fragment.selectionSet.selections,
            isDeferred: isDeferred || isNewlyDeferred,
          ),
        );
      case CoercionSuccess():
        throw StateError('A defer condition is a boolean.');
      case final CoercionFailure failure:
        return _Failed(failure.problems.first);
    }
  }

  // Spec 6.3.2 `DoesFragmentTypeApply`: no condition always applies; an
  // object type applies to itself; an abstract type to its possible types.
  bool _matches(NamedType? condition, ObjectType runtimeType) {
    if (condition == null) {
      return true;
    }
    final type = context.schema.typeNamed(condition.name.value);
    if (type == null) {
      return false;
    }
    if (type.name == runtimeType.name) {
      return true;
    }
    return context.schema.isSubType(type, runtimeType);
  }
}

// A position in a list of selections.
final class _Frame {
  _Frame(this._selections, {required this.isDeferred});

  final List<Selection> _selections;
  final bool isDeferred;
  int _index = 0;

  bool get isFinished => _index >= _selections.length;

  Selection next() => _selections[_index++];
}

sealed class _Step {
  const _Step();
}

final class _Done extends _Step {
  const _Done();
}

final class _Descend extends _Step {
  const _Descend(this.frame);

  final _Frame frame;
}

final class _Failed extends _Step {
  const _Failed(this.problem);

  final CoercionProblem problem;
}
