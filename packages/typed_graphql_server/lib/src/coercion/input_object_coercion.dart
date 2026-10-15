import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_messages.dart';
import 'input_object_decoder.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'value_coercion.dart';
import 'value_inspector.dart';

/// Coerces a JSON object to an input object (spec 3.10) with graphql-js's
/// `validateInputValue` messages and order: the declared fields in
/// declaration order, then the unknown ones, then the `@oneOf` rule; then
/// the definition's `decode` builds the Dart value.
final class InputObjectCoercion {
  /// Coerces into [problems]; fields go back through [values].
  InputObjectCoercion(this.environment, this.problems, this.values);

  static const ValueInspector _inspector = ValueInspector();
  static const LiteralConverter _converter = LiteralConverter();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  /// Coerces the values of the fields.
  final ValueCoercion values;

  InputMessages get _messages =>
      InputMessages(includesSuggestions: environment.includesSuggestions);

  /// The Dart value of [value] for [type] at [path].
  Object? coerce(
    JsonValue value,
    InputObjectType type,
    InputPath path,
    int depth,
  ) {
    if (value is! JsonObject) {
      problems.add(
        _messages.notObject(type.name, _inspector.inspect(value)),
        path,
      );
      return InvalidValue.instance;
    }
    final coerced = <String, Object?>{};
    var isValid = _coerceFields(value, type, coerced, path, depth);
    isValid = _checkUnknown(value, type, path) && isValid;
    isValid = (!type.isOneOf || _checkOneOf(value, type, path)) && isValid;
    return isValid
        ? InputObjectDecoder(environment, problems).decode(coerced, type, path)
        : InvalidValue.instance;
  }

  bool _coerceFields(
    JsonObject value,
    InputObjectType type,
    Map<String, Object?> coerced,
    InputPath path,
    int depth,
  ) {
    var isValid = true;
    for (final field in type.fields) {
      if (problems.hasOverflowed) {
        return false;
      }
      final given = value.fields[field.name];
      final result = given == null
          ? _absent(value, type, field, path, depth)
          : values.coerce(given, field.type, path.key(field.name), depth + 1);
      if (result is InvalidValue) {
        isValid = false;
      } else if (given != null || field.defaultValue != null) {
        coerced[field.name] = result;
      }
    }
    return isValid;
  }

  // A missing field is an error when required, its default otherwise.
  Object? _absent(
    JsonObject value,
    InputObjectType type,
    InputValue field,
    InputPath path,
    int depth,
  ) {
    final defaultValue = field.defaultValue;
    if (defaultValue != null) {
      return _default(defaultValue, field, path.key(field.name), depth);
    }
    if (field.type is NonNullType) {
      problems.add(
        _messages.missingField(
          type.name,
          field.name,
          _inspector.inspect(value),
        ),
        path,
      );
      return InvalidValue.instance;
    }
    return null;
  }

  Object? _default(
    Value literal,
    InputValue field,
    InputPath path,
    int depth,
  ) => switch (_converter.convert(literal)) {
    DecodeSuccess(:final value) => values.coerce(
      value,
      field.type,
      path,
      depth + 1,
    ),
    DecodeFailure(:final message) => _reject(message, path),
  };

  InvalidValue _reject(String message, InputPath path) {
    problems.add(message, path);
    return InvalidValue.instance;
  }

  bool _checkUnknown(JsonObject value, InputObjectType type, InputPath path) {
    final names = [for (final field in type.fields) field.name];
    final known = names.toSet();
    var isValid = true;
    for (final name in value.fields.keys) {
      if (known.contains(name)) {
        continue;
      }
      isValid = false;
      if (problems.hasOverflowed) {
        break;
      }
      problems.add(
        _messages.unknownField(
          type.name,
          name,
          names,
          _inspector.inspect(value),
        ),
        path,
      );
    }
    return isValid;
  }

  bool _checkOneOf(JsonObject value, InputObjectType type, InputPath path) {
    final message = _messages.oneOf(type.name);
    final known = {for (final field in type.fields) field.name};
    final given = [
      for (final name in value.fields.keys)
        if (known.contains(name)) name,
    ];
    var isValid = given.length == 1;
    if (!isValid) {
      problems.add(message, path);
    }
    if (given.isNotEmpty && value.fields[given.first] is JsonNull) {
      problems.add(message, path.key(given.first));
      isValid = false;
    }
    return isValid;
  }
}
