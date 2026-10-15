import 'dart:math';

import '../../language/ast/selection.dart';
import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import '../../protocol/json_value.dart';
import '../../schema/model/schema_field.dart';
import 'cost_weights.dart';
import 'list_size_setting.dart';
import 'sized_context.dart';

/// How many items a field node is assumed to return (IBM cost draft), and
/// which of its children `sizedFields` sizes.
final class ListSizes(
  /// The weights and `@listSize` settings.
  final CostWeights weights,

  /// The size of a list field the schema says nothing about.
  final int defaultListSize,

  /// The values of the operation's variables.
  final Map<String, JsonValue> variables,

  /// The default value of each variable that has one.
  final Map<String, Value> variableDefaults,
) {
  /// Creates the calculation.
  this;

  /// The size of [node], a use of [definition], inside [sized], and the
  /// context it gives its own selection set (null when `@listSize` has no
  /// `sizedFields`).
  ///
  /// A field with `sizedFields` has size 1 and passes the size it would
  /// have to the children named; a field that its parent sized takes that
  /// size.
  ({double size, SizedContext? childContext}) of(
    Field node,
    SchemaField definition,
    SizedContext? sized,
  ) {
    final setting = weights.listSizeOf(definition);
    final computed = _computed(node, definition, setting);
    if (setting != null && setting.sizedFields.isNotEmpty) {
      return (
        size: 1.0,
        childContext: SizedContext({...setting.sizedFields}, computed),
      );
    }
    if (sized != null && sized.names.contains(node.name.value)) {
      return (size: sized.size, childContext: null);
    }
    return (size: computed, childContext: null);
  }

  double _computed(
    Field node,
    SchemaField definition,
    ListSizeSetting? setting,
  ) {
    final isList = _unwrapNonNull(definition.type) is ListType;
    if (setting == null) {
      return isList ? defaultListSize.toDouble() : 1.0;
    }
    if (!isList && setting.sizedFields.isEmpty) {
      return 1;
    }
    final sliced = _sliced(node, definition, setting);
    return sliced ?? setting.assumedSize ?? defaultListSize.toDouble();
  }

  double? _sliced(Field node, SchemaField definition, ListSizeSetting setting) {
    double? largest;
    for (final name in setting.slicingArguments) {
      for (final argument in node.arguments) {
        if (argument.name.value == name) {
          largest = _largest(largest, _valueOf(argument.value));
        }
      }
    }
    if (largest != null) {
      return largest;
    }
    for (final name in setting.slicingArguments) {
      final fallback = definition.argumentNamed(name)?.defaultValue;
      largest = _largest(largest, _count(fallback));
    }
    return largest;
  }

  double? _largest(double? first, double? second) => switch ((first, second)) {
    (final a?, final b?) => max(a, b),
    (final a?, null) => a,
    (null, final b) => b,
  };

  // The number a slicing argument's value stands for; null for a value that
  // names no size, such as null.
  double? _valueOf(Value value) => switch (value) {
    Variable(:final name) => _variable(name.value),
    _ => _count(value),
  };

  // The size a variable gives: its value, or its default when it has no
  // value. Null when it names no size (an explicit null, which overrides the
  // default as in September2025 6.4.1, a non-number, a negative number, or
  // neither a value nor a default): the field is then sized as if the
  // argument were not given, so a client cannot lower the cost (R5.14).
  double? _variable(String name) => switch (variables[name]) {
    JsonNumber(:final value) => _size(value.toDouble()),
    null => _count(variableDefaults[name]),
    _ => null,
  };

  double? _count(Value? value) => switch (value) {
    IntValue(:final value) => switch (double.tryParse(value)) {
      final number? => _size(number),
      null => null,
    },
    _ => null,
  };

  // A negative number names no size. A whole number past the safe-integer
  // range (or a fraction) is still the size the caller meant; a 400-digit
  // literal parses to Infinity, so sizes stay finite and no product of costs
  // is NaN (`SaturatingCost`).
  double? _size(double size) =>
      size < 0 ? null : min<double>(double.maxFinite, size);

  // Loops, not recursion: a wrapper chain can be deep.
  TypeRef _unwrapNonNull(TypeRef type) {
    var current = type;
    while (current is NonNullType) {
      current = current.type;
    }
    return current;
  }
}
