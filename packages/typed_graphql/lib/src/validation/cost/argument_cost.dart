import '../../language/ast/argument.dart';
import '../../language/ast/value.dart';
import '../../schema/model/input_value.dart';
import '../../schema/model/schema_type.dart';
import '../../schema/schema.dart';
import 'cost_weights.dart';

/// The cost of the arguments written on a field or a directive (IBM cost
/// draft): the weight of each argument given plus the weight of each input
/// field written in its value.
final class ArgumentCost(
  /// The schema that defines the arguments.
  final Schema schema,

  /// The weights of its elements.
  final CostWeights weights,
) {
  /// Creates the calculation.
  this;

  /// The cost of [arguments], whose definitions [definitionNamed] finds.
  ///
  /// An argument or input field the schema does not define adds 0, and so
  /// does everything written inside an unknown input field. A variable adds
  /// only its argument's weight. The value is walked with a stack, because
  /// a value can be nested very deeply.
  double of(
    List<Argument> arguments,
    InputValue? Function(String name) definitionNamed,
  ) {
    var total = 0.0;
    for (final argument in arguments) {
      if (definitionNamed(argument.name.value) case final definition?) {
        total += weights.ofInputValue(definition);
        total += _inside(
          argument.value,
          schema.namedTypeOf(definition.type),
        );
      }
    }
    return total;
  }

  double _inside(Value value, SchemaType? type) {
    var total = 0.0;
    final stack = [(value, type)];
    while (stack.isNotEmpty) {
      final (current, currentType) = stack.removeLast();
      switch (current) {
        case ListValue(:final values):
          stack.addAll([for (final item in values) (item, currentType)]);
        case ObjectValue(:final fields) when currentType is InputObjectType:
          for (final field in fields) {
            if (currentType.fieldNamed(field.name.value) case final input?) {
              total += weights.ofInputValue(input);
              stack.add((field.value, schema.namedTypeOf(input.type)));
            }
          }
        default:
          break;
      }
    }
    return total;
  }
}
