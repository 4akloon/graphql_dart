import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'literal_leaf_coercion.dart';
import 'object_literal_coercion.dart';
import 'value_coercion.dart';

/// Coerces a literal of a document, with variables in it, to a Dart value
/// (graphql-js's `coerceInputLiteral` with the messages of
/// `validateInputLiteral`, September2025 section 6.4.1).
///
/// A variable stands for its already coerced Dart value, so a literal
/// cannot go through JSON first. Like [ValueCoercion] it recurses along the
/// literal, and one nested deeper than [ValueCoercion.maxDepth] is a
/// problem. Problems go to [problems]; a step that finds one returns
/// [InvalidValue.instance].
final class LiteralCoercion {
  /// Coerces into [problems], reading variables from [variables] (the
  /// coerced values by name; a variable that is not a key has no value).
  LiteralCoercion(this.environment, this.problems, this.variables)
    : _leaves = LiteralLeafCoercion(environment, problems);

  static const Printer _printer = Printer();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  /// The coerced variable values.
  final Map<String, Object?> variables;

  final LiteralLeafCoercion _leaves;

  /// The Dart value of [literal] for [type] at [path], [depth] levels of
  /// lists and input objects below the top.
  Object? coerce(Value literal, TypeRef type, InputPath path, int depth) {
    if (problems.hasOverflowed) {
      return InvalidValue.instance;
    }
    if (depth > ValueCoercion.maxDepth) {
      return _reject('Input value is nested too deeply.', path);
    }
    if (literal is Variable) {
      return _variable(literal, type, path);
    }
    return switch (type) {
      NonNullType(type: final wrapped) =>
        literal is NullValue
            ? _reject(
                'Expected value of non-null type "${_printer.print(type)}" '
                'not to be null.',
                path,
              )
            : coerce(literal, wrapped, path, depth),
      _ when literal is NullValue => null,
      ListType(type: final item) => _list(literal, item, path, depth),
      NamedType(:final name) => _named(literal, name.value, path, depth),
    };
  }

  InvalidValue _reject(String message, InputPath path) {
    problems.add(message, path);
    return InvalidValue.instance;
  }

  // Not validated against its type: validation did that (spec 5.8.5).
  Object? _variable(Variable variable, TypeRef type, InputPath path) {
    final name = variable.name.value;
    if (type is NonNullType) {
      final printed = _printer.print(type);
      if (!variables.containsKey(name)) {
        return _reject(
          'Expected variable "\$$name" provided to type "$printed" to '
          'provide a runtime value.',
          path,
        );
      }
      if (variables[name] == null) {
        return _reject(
          'Expected variable "\$$name" provided to non-null type "$printed" '
          'not to be null.',
          path,
        );
      }
    }
    return variables[name];
  }

  // A value that is not a list stands for a list of one (spec 3.11); a
  // variable without a value in a list is null.
  Object? _list(Value literal, TypeRef item, InputPath path, int depth) {
    if (literal is! ListValue) {
      final single = coerce(literal, item, path, depth + 1);
      return single is InvalidValue ? single : <Object?>[single];
    }
    final result = <Object?>[];
    var isValid = true;
    for (final (index, node) in literal.values.indexed) {
      if (problems.hasOverflowed) {
        break;
      }
      final coerced = coerce(node, item, path.index(index), depth + 1);
      if (coerced is InvalidValue) {
        isValid = false;
      } else {
        result.add(coerced);
      }
    }
    return isValid ? result : InvalidValue.instance;
  }

  Object? _named(Value literal, String name, InputPath path, int depth) =>
      switch (environment.schema.typeNamed(name)) {
        final InputObjectType type => ObjectLiteralCoercion(
          environment,
          problems,
          variables,
          this,
        ).coerce(literal, type, path, depth),
        final ScalarType type => _leaves.coerce(literal, type, path),
        final EnumType type => _leaves.coerce(literal, type, path),
        _ => _reject('Type "$name" is not an input type.', path),
      };
}
