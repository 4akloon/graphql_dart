import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_problem.dart';
import 'coercion_result.dart';
import 'input_coercion.dart';
import 'variable_coercion_result.dart';
import 'variable_errors.dart';

/// September2025 section 6.4.1 `CoerceVariableValues` with graphql-js 17's
/// `getVariableValues` messages: it coerces the request's variable values
/// against an operation's variable definitions (R4.7).
///
/// Errors are request errors: no data is produced. At most
/// [maxCoercionErrors] are kept, then one "Too many errors" error
/// (`GQL312`).
final class VariableCoercion {
  /// Coerces with [coercion].
  VariableCoercion(this._coercion, {this.maxCoercionErrors = 50});

  static const Printer _printer = Printer();

  final InputCoercion _coercion;

  /// The most coercion errors reported.
  final int maxCoercionErrors;

  /// Coerces [inputs] (null for none) against [definitions]. With a
  /// [source], each error has the location of its variable definition.
  VariableCoercionResult coerce(
    List<VariableDefinition> definitions,
    JsonObject? inputs, {
    Source? source,
  }) {
    final errors = VariableErrors(maxCoercionErrors, source);
    final values = <String, Object?>{};
    for (final definition in definitions) {
      if (errors.isStopped) {
        break;
      }
      _coerceOne(definition, inputs, values, errors);
    }
    if (errors.errors.isEmpty) {
      return CoercedVariables(values);
    }
    return VariableCoercionFailure(errors.errors, errors.unexpected);
  }

  void _coerceOne(
    VariableDefinition definition,
    JsonObject? inputs,
    Map<String, Object?> values,
    VariableErrors errors,
  ) {
    final name = definition.variable.name.value;
    final type = definition.type;
    if (!_coercion.isInputType(type)) {
      errors.report(
        'Variable "\$$name" expected value of type "${_printer.print(type)}" '
        'which cannot be used as an input type.',
        DiagnosticCode.invalidVariableValue,
        type.start,
      );
      return;
    }
    final given = inputs?.fields[name];
    final fallback = definition.defaultValue;
    final result = _resultFor(given, fallback, type, errors.remaining);
    final isDefault = given == null && fallback != null;
    switch (result) {
      case null:
        break;
      case CoercionSuccess(:final value):
        values[name] = value;
      case CoercionFailure():
        _report(result, definition, isDefault: isDefault, errors: errors);
    }
  }

  // Null: nothing to record, the variable is simply absent.
  CoercionResult? _resultFor(
    JsonValue? given,
    Value? fallback,
    TypeRef type,
    int maxProblems,
  ) => switch ((given, fallback)) {
    (final JsonValue value, _) => _coercion.coerceValue(
      value,
      type,
      maxProblems: maxProblems,
    ),
    (_, final Value literal) => _coercion.coerceLiteral(
      literal,
      type,
      maxProblems: maxProblems,
    ),
    _ when type is! NonNullType => null,
    _ => _missing(type),
  };

  void _report(
    CoercionFailure failure,
    VariableDefinition definition, {
    required bool isDefault,
    required VariableErrors errors,
  }) {
    final name = definition.variable.name.value;
    errors.reportFailure(
      failure,
      'Variable "\$$name" has invalid ${isDefault ? 'default value' : 'value'}',
      isDefault
          ? DiagnosticCode.invalidVariableDefault
          : DiagnosticCode.invalidVariableValue,
      definition.start,
    );
  }

  // A required variable that the request did not give.
  CoercionResult _missing(TypeRef type) => CoercionFailure([
    CoercionProblem(
      'Expected a value of non-null type "${_printer.print(type)}" '
          'to be provided.',
      '',
    ),
  ], hasOverflowed: false);
}
