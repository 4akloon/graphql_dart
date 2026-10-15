import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'leaf_coercion.dart';

/// Coerces a literal to a scalar or an enum value with graphql-js's
/// `coerceInputLiteral` rules: a literal has a kind, and the kind matters
/// where JSON does not tell (an enum literal is never a string, a string
/// literal is never an enum value, `1.0` is no `Int`).
///
/// The kinds a built-in scalar accepts are checked here; the value itself
/// goes through [LeafCoercion] as the JSON the literal stands for.
final class LiteralLeafCoercion {
  /// Coerces into [problems].
  LiteralLeafCoercion(this.environment, this.problems)
    : _leaves = LeafCoercion(environment, problems);

  static const Printer _printer = Printer();
  static const LiteralConverter _converter = LiteralConverter();

  // The message of each built-in scalar for a literal of a kind it refuses.
  static const Map<String, String> _refusals = {
    'Int': 'Int cannot represent non-integer value',
    'Float': 'Float cannot represent non numeric value',
    'String': 'String cannot represent a non string value',
    'Boolean': 'Boolean cannot represent a non boolean value',
    'ID': 'ID cannot represent a non-string and non-integer value',
  };

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  final LeafCoercion _leaves;

  /// The Dart value of the constant [literal] for the leaf [type] at
  /// [path].
  Object? coerce(Value literal, SchemaType type, InputPath path) {
    if (type is EnumType && literal is! EnumValue) {
      final printed = _printer.print(literal);
      problems.add(
        'Enum "${type.name}" cannot represent non-enum value: $printed.'
        '${_leaves.suggestEnumValue(printed, type)}',
        path,
      );
      return InvalidValue.instance;
    }
    if (type is ScalarType && !_accepts(type.name, literal)) {
      problems.add('${_refusals[type.name]}: ${_printer.print(literal)}', path);
      return InvalidValue.instance;
    }
    return switch (_converter.convert(literal)) {
      DecodeSuccess(:final value) => _leaves.coerce(value, type, path),
      DecodeFailure(:final message) => _reject(message, path),
    };
  }

  InvalidValue _reject(String message, InputPath path) {
    problems.add(message, path);
    return InvalidValue.instance;
  }

  // A scalar that is not built in takes any literal; its codec decides.
  bool _accepts(String scalar, Value literal) => switch (scalar) {
    'Int' => literal is IntValue,
    'Float' => literal is IntValue || literal is FloatValue,
    'String' => literal is StringValue,
    'Boolean' => literal is BooleanValue,
    'ID' => literal is StringValue || literal is IntValue,
    _ => true,
  };
}
