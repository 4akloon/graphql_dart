import 'dart:math';

import '../../language/ast/executable_definition.dart';
import '../../language/ast/selection.dart';
import '../../schema/model/schema_field.dart';
import '../../schema/model/schema_type.dart';
import '../../schema/schema.dart';
import '../meta_fields.dart';
import 'argument_cost.dart';
import 'cost_weights.dart';
import 'list_sizes.dart';
import 'saturating_cost.dart';
import 'sized_context.dart';

/// One computation of an operation's cost: walks the selections with an
/// explicit stack and memoises each fragment.
///
/// A fragment's cost depends only on the fragment and the [SizedContext] in
/// effect where it is spread, so it is computed once per pair and a chain of
/// fragments that expands exponentially costs one visit each. A fragment on
/// the stack when it is spread again is a cycle and counts 0, like an unknown
/// fragment. The costs are sums and products of doubles, saturated at the
/// largest finite double ([SaturatingCost]): never NaN or infinite.
///
/// A fragment cut by a cycle is memoised like any other, so on a document
/// with fragment cycles (which `NoFragmentCyclesRule` reports) its cost can
/// depend on which fragment is entered first; it is still deterministic and
/// an upper bound is not claimed there.
final class CostWalk(
  /// The schema.
  final Schema schema,

  /// The weights.
  final CostWeights weights,

  /// The list sizes.
  final ListSizes sizes,

  /// The fragments of the document by name; the last definition wins.
  final Map<String, FragmentDefinition> fragments,
) {
  /// Creates a walk.
  this;

  final Map<String, ({double fieldCost, double typeCost})> _memo = {};
  late final ArgumentCost _arguments = ArgumentCost(schema, weights);

  /// The field cost and the type cost of [operation].
  ({double fieldCost, double typeCost}) cost(OperationDefinition operation) {
    final rootName = schema.rootTypeName(operation.operation);
    final root = rootName == null ? null : schema.typeNamed(rootName);
    if (root == null) {
      return (fieldCost: 0.0, typeCost: 0.0);
    }
    final selections = _selectionsCost(operation.selectionSet.selections, root);
    return (
      fieldCost: selections.fieldCost,
      typeCost: weights.ofType(root) + selections.typeCost,
    );
  }

  ({double fieldCost, double typeCost}) _selectionsCost(
    List<Selection> selections,
    SchemaType root,
  ) {
    final inProgress = <String>{};
    final stack = [_Frame(selections, root, null)];
    while (true) {
      final frame = stack.last;
      if (frame.index < frame.selections.length) {
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
      if (frame.fragmentName case final name?) {
        inProgress.remove(name);
        _memo['$name|${frame.sized?.key}'] = (
          fieldCost: frame.fieldCost,
          typeCost: frame.typeCost,
        );
      }
      if (stack.isEmpty) {
        return (fieldCost: frame.fieldCost, typeCost: frame.typeCost);
      }
      stack.last.add(
        frame.rawCost.plus(frame.multiplier.times(frame.fieldCost)),
        frame.multiplier.times(frame.typeWeight.plus(frame.typeCost)),
      );
    }
  }

  // Adds the cost of [selection] to [frame] when it needs no walk, else
  // returns the frame that computes it.
  _Frame? _visit(Selection selection, _Frame frame, Set<String> inProgress) {
    switch (selection) {
      case Field():
        return _field(selection, frame);
      case InlineFragment(:final typeCondition, :final selectionSet):
        final parent = switch (typeCondition) {
          final condition? => schema.typeNamed(condition.name.value),
          null => frame.parentType,
        };
        return _Frame(selectionSet.selections, parent, frame.sized);
      case FragmentSpread(:final name):
        return _spread(name.value, frame, inProgress);
    }
  }

  _Frame? _spread(String name, _Frame frame, Set<String> inProgress) {
    final fragment = fragments[name];
    if (fragment == null || inProgress.contains(name)) {
      return null;
    }
    if (_memo['$name|${frame.sized?.key}'] case final known?) {
      frame.add(known.fieldCost, known.typeCost);
      return null;
    }
    inProgress.add(name);
    return _Frame(
      fragment.selectionSet.selections,
      schema.typeNamed(fragment.typeCondition.name.value),
      frame.sized,
      fragmentName: name,
    );
  }

  _Frame? _field(Field node, _Frame frame) {
    final definition = _definitionOf(node, frame.parentType);
    if (definition == null) {
      return null;
    }
    final raw = max<double>(
      0,
      weights
          .ofField(definition)
          .plus(_arguments.of(node.arguments, definition.argumentNamed))
          .plus(_directives(node)),
    );
    final size = sizes.of(node, definition, frame.sized);
    final typeWeight = weights.ofNamedTypeIn(definition.type);
    final named = schema.namedTypeOf(definition.type);
    final selectionSet = node.selectionSet;
    if (selectionSet == null || named == null) {
      frame.add(raw, size.size.times(typeWeight));
      return null;
    }
    return _Frame(
      selectionSet.selections,
      named,
      size.childContext,
      rawCost: raw,
      typeWeight: typeWeight,
      multiplier: size.size,
    );
  }

  // A meta-field is free and so is a field the parent does not define.
  SchemaField? _definitionOf(Field node, SchemaType? parent) {
    final name = node.name.value;
    if (parent == null || name.startsWith('__')) {
      return null;
    }
    return MetaFields.fieldOf(schema, parent, name);
  }

  double _directives(Field node) {
    var total = 0.0;
    for (final directive in node.directives) {
      if (schema.directiveNamed(directive.name.value) case final definition?) {
        total = total.plus(
          _arguments.of(directive.arguments, definition.argumentNamed),
        );
      }
    }
    return total;
  }
}

// A selection set being summed. When it is popped, its sum goes to the frame
// below as `rawCost + multiplier * fieldCost` and `multiplier * (typeWeight +
// typeCost)`: a field's own cost and the size of its list.
final class _Frame(
  final List<Selection> selections,
  final SchemaType? parentType,
  final SizedContext? sized, {
  final String? fragmentName,
  final double rawCost = 0,
  final double typeWeight = 0,
  final double multiplier = 1,
}) {
  this;

  int index = 0;
  double fieldCost = 0;
  double typeCost = 0;

  void add(double field, double type) {
    fieldCost = fieldCost.plus(field);
    typeCost = typeCost.plus(type);
  }
}
