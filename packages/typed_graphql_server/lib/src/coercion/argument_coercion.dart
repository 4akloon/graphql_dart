import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_environment.dart';
import 'coercion_problem.dart';
import 'coercion_problems.dart';
import 'coercion_result.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'literal_coercion.dart';

/// September2025 section 6.4.1 `CoerceArgumentValues` with graphql-js 17's
/// `getArgumentValues` messages: it coerces the arguments written on a field
/// or a directive against the arguments the schema declares (R4.7).
///
/// Like graphql-js it stops at the first argument that fails, and a failure
/// holds one problem: the message is complete (`Argument
/// "Query.user(id:)" has invalid value at .a: ...`) and the code is
/// `GQL313` unless the cause has its own. A success holds the coerced
/// values by argument name, defaults included; an argument that is not
/// there was not given.
final class ArgumentCoercion {
  /// Coerces in [environment].
  ArgumentCoercion(this.environment);

  static const Printer _printer = Printer();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Coerces the [nodes] written on the field or directive named [owner]
  /// (`Query.user`, `@skip`) against its [declared] arguments, reading
  /// variables from [variables] (the coerced values by name).
  CoercionResult coerce(
    String owner,
    List<InputValue> declared,
    List<Argument> nodes,
    Map<String, Object?> variables,
  ) {
    final written = {for (final node in nodes) node.name.value: node.value};
    final values = <String, Object?>{};
    for (final definition in declared) {
      final subject = 'Argument "$owner(${definition.name}:)"';
      final problem = _coerceOne(
        subject,
        definition,
        written[definition.name],
        variables,
        values,
      );
      if (problem != null) {
        return CoercionFailure([problem], hasOverflowed: false);
      }
    }
    return CoercionSuccess(values);
  }

  CoercionProblem? _coerceOne(
    String subject,
    InputValue definition,
    Value? written,
    Map<String, Object?> variables,
    Map<String, Object?> values,
  ) {
    final isRequired =
        definition.type is NonNullType && definition.defaultValue == null;
    if (written == null && isRequired) {
      return _problem(
        '$subject of required type "${_printer.print(definition.type)}" was '
        'not provided.',
      );
    }
    // A variable without a value counts as no argument unless required.
    final isAbsent =
        written == null ||
        (written is Variable &&
            !variables.containsKey(written.name.value) &&
            !isRequired);
    return isAbsent
        ? _useDefault(subject, definition, values)
        : _useLiteral(subject, definition, written, variables, values);
  }

  CoercionProblem? _useDefault(
    String subject,
    InputValue definition,
    Map<String, Object?> values,
  ) {
    final fallback = definition.defaultValue;
    if (fallback == null) {
      return null;
    }
    final problems = CoercionProblems(1);
    final coerced = LiteralCoercion(
      environment,
      problems,
      const <String, Object?>{},
    ).coerce(fallback, definition.type, InputPath.root, 0);
    if (coerced is InvalidValue) {
      return _problem(
        '$subject has invalid default value',
        problem: problems.kept.first,
      );
    }
    values[definition.name] = coerced;
    return null;
  }

  CoercionProblem? _useLiteral(
    String subject,
    InputValue definition,
    Value written,
    Map<String, Object?> variables,
    Map<String, Object?> values,
  ) {
    final problems = CoercionProblems(1);
    final coerced = LiteralCoercion(
      environment,
      problems,
      variables,
    ).coerce(written, definition.type, InputPath.root, 0);
    if (coerced is InvalidValue) {
      return _problem(
        '$subject has invalid value',
        problem: problems.kept.first,
        node: written,
      );
    }
    values[definition.name] = coerced;
    return null;
  }

  // Words `[lead][where]: [message]` of a cause, or a plain message.
  CoercionProblem _problem(
    String lead, {
    CoercionProblem? problem,
    Node? node,
  }) {
    if (problem == null) {
      return CoercionProblem(
        lead,
        '',
        code: DiagnosticCode.invalidArgumentValue,
      );
    }
    return CoercionProblem(
      '$lead${problem.where}: ${problem.message}',
      '',
      code: problem.code ?? DiagnosticCode.invalidArgumentValue,
      extensions: problem.extensions,
      thrown: problem.thrown,
      node: node,
    );
  }
}
