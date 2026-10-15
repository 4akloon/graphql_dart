import 'package:typed_graphql/typed_graphql.dart';

import '../execution/schema_bindings.dart';
import 'coercion_environment.dart';
import 'coercion_problem.dart';
import 'coercion_problems.dart';
import 'coercion_result.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'value_coercion.dart';

/// Coerces input values (variables, input object fields, defaults) to Dart
/// values against a core type, with the schema's scalar codecs, enum
/// definitions and input object `decode` (September2025 section 3.11,
/// graphql-js's `coerceInputValue` and `validateInputValue`; R4.7).
///
/// It never throws: an invalid value is a [CoercionFailure] with graphql-js's
/// messages and the paths of the places.
final class InputCoercion {
  /// Coerces against [schema] with the Dart definitions in [bindings].
  /// [includesSuggestions] turns "Did you mean" text on or off.
  InputCoercion(
    Schema schema,
    SchemaBindings bindings, {
    bool includesSuggestions = true,
  }) : _environment = CoercionEnvironment(
         schema,
         bindings,
         includesSuggestions: includesSuggestions,
       );

  /// The default of [maxProblems].
  static const int defaultMaxProblems = 50;

  final CoercionEnvironment _environment;

  /// Whether [type] names an input type of the schema.
  bool isInputType(TypeRef type) => _environment.schema.isInputType(type);

  /// The Dart value of the JSON [value] for [type], or at most
  /// [maxProblems] problems.
  CoercionResult coerceValue(
    JsonValue value,
    TypeRef type, {
    int maxProblems = defaultMaxProblems,
  }) {
    final problems = CoercionProblems(maxProblems);
    final coerced = ValueCoercion(
      _environment,
      problems,
    ).coerce(value, type, InputPath.root, 0);
    if (coerced is InvalidValue) {
      return CoercionFailure(
        problems.kept,
        hasOverflowed: problems.hasOverflowed,
      );
    }
    return CoercionSuccess(coerced);
  }

  /// The Dart value of the constant [literal] for [type]: the literal goes
  /// through `LiteralConverter`, then [coerceValue] (an enum literal is its
  /// name). A literal with a variable in it is a problem.
  CoercionResult coerceLiteral(
    Value literal,
    TypeRef type, {
    int maxProblems = defaultMaxProblems,
  }) => switch (const LiteralConverter().convert(literal)) {
    DecodeSuccess(:final value) => coerceValue(
      value,
      type,
      maxProblems: maxProblems,
    ),
    DecodeFailure(:final message) => CoercionFailure([
      CoercionProblem(message, ''),
    ], hasOverflowed: false),
  };
}
