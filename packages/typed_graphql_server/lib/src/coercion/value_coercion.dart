import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_object_coercion.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'leaf_coercion.dart';

/// Coerces a JSON value against a type: non-null, list and named types
/// (September2025 section 3.11 and graphql-js's `coerceInputValue`), handing
/// leaves and input objects to their collaborators.
///
/// It recurses along the value, as `JsonReader` does, so a value nested
/// deeper than [maxDepth] is a problem and never a stack overflow (spec
/// 4.4). Problems go to [problems]; a step that finds one returns
/// [InvalidValue.instance].
final class ValueCoercion {
  /// Coerces into [problems].
  ValueCoercion(this.environment, this.problems)
    : _leaves = LeafCoercion(environment, problems);

  /// The deepest nesting of lists and input objects coercion follows.
  static const int maxDepth = JsonReader.maxSupportedDepth;

  static const Printer _printer = Printer();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  final LeafCoercion _leaves;

  /// The Dart value of [value] for [type] at [path], [depth] levels of lists
  /// and input objects below the top.
  Object? coerce(JsonValue value, TypeRef type, InputPath path, int depth) {
    if (problems.hasOverflowed) {
      return InvalidValue.instance;
    }
    if (depth > maxDepth) {
      problems.add('Input value is nested too deeply.', path);
      return InvalidValue.instance;
    }
    return switch (type) {
      NonNullType(type: final wrapped) =>
        value is JsonNull
            ? _reject(
                'Expected value of non-null type "${_printer.print(type)}" '
                'not to be null.',
                path,
              )
            : coerce(value, wrapped, path, depth),
      _ when value is JsonNull => null,
      ListType(type: final item) => _list(value, item, path, depth),
      NamedType(:final name) => _named(value, name.value, path, depth),
    };
  }

  InvalidValue _reject(String message, InputPath path) {
    problems.add(message, path);
    return InvalidValue.instance;
  }

  // A value that is not a list stands for a list of one (spec 3.11).
  Object? _list(JsonValue value, TypeRef item, InputPath path, int depth) {
    if (value is! JsonArray) {
      final single = coerce(value, item, path, depth + 1);
      return single is InvalidValue ? single : <Object?>[single];
    }
    final result = <Object?>[];
    var isValid = true;
    for (var i = 0; i < value.items.length && !problems.hasOverflowed; i++) {
      final coerced = coerce(value.items[i], item, path.index(i), depth + 1);
      if (coerced is InvalidValue) {
        isValid = false;
      } else {
        result.add(coerced);
      }
    }
    return isValid ? result : InvalidValue.instance;
  }

  Object? _named(JsonValue value, String name, InputPath path, int depth) =>
      switch (environment.schema.typeNamed(name)) {
        final InputObjectType type => InputObjectCoercion(
          environment,
          problems,
          this,
        ).coerce(value, type, path, depth),
        final ScalarType type => _leaves.coerce(value, type, path),
        final EnumType type => _leaves.coerce(value, type, path),
        _ => _reject('Type "$name" is not an input type.', path),
      };
}
