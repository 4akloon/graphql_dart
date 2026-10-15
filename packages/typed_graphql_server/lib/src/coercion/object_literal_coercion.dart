import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_messages.dart';
import 'input_object_decoder.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'literal_coercion.dart';

/// Coerces an object literal to an input object (spec 3.10) with the
/// messages and the order of graphql-js's `validateInputLiteral`: the
/// declared fields in declaration order, then the unknown ones, then the
/// `@oneOf` rule; then the definition's `decode` builds the Dart value.
final class ObjectLiteralCoercion {
  /// Coerces into [problems], reading variables from [variables]; the
  /// values of the fields go back through [literals].
  ObjectLiteralCoercion(
    this.environment,
    this.problems,
    this.variables,
    this.literals,
  );

  static const Printer _printer = Printer();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  /// The coerced variable values.
  final Map<String, Object?> variables;

  /// Coerces the values of the fields.
  final LiteralCoercion literals;

  InputMessages get _messages =>
      InputMessages(includesSuggestions: environment.includesSuggestions);

  /// The Dart value of the object [literal] for [type] at [path], [depth]
  /// levels below the top.
  Object? coerce(
    Value literal,
    InputObjectType type,
    InputPath path,
    int depth,
  ) {
    if (literal is! ObjectValue) {
      return _reject(
        _messages.notObject(type.name, _printer.print(literal)),
        path,
      );
    }
    final coerced = <String, Object?>{};
    var isValid = _coerceFields(literal, type, coerced, path, depth);
    isValid = _checkUnknown(literal, type, path) && isValid;
    isValid = (!type.isOneOf || _checkOneOf(literal, type, path)) && isValid;
    return isValid
        ? InputObjectDecoder(environment, problems).decode(coerced, type, path)
        : InvalidValue.instance;
  }

  bool _coerceFields(
    ObjectValue literal,
    InputObjectType type,
    Map<String, Object?> coerced,
    InputPath path,
    int depth,
  ) {
    final nodes = {for (final f in literal.fields) f.name.value: f.value};
    var isValid = true;
    for (final field in type.fields) {
      if (problems.hasOverflowed) {
        return false;
      }
      final result = _field(literal, type, field, nodes[field.name], (
        path,
        depth,
      ));
      if (result == null) {
        continue;
      }
      if (result.value is InvalidValue) {
        isValid = false;
      } else {
        coerced[field.name] = result.value;
      }
    }
    return isValid;
  }

  // Null: the field has no value and no default, so it is left out.
  ({Object? value})? _field(
    ObjectValue literal,
    InputObjectType type,
    InputValue field,
    Value? given,
    (InputPath, int) place,
  ) {
    final (path, depth) = place;
    if (given is Variable &&
        type.isOneOf &&
        _isOneOfVariableBad(given, type, field, path)) {
      return (value: InvalidValue.instance);
    }
    final isMissing =
        given == null ||
        (given is Variable &&
            !variables.containsKey(given.name.value) &&
            !_isRequired(field));
    if (!isMissing) {
      return (
        value: literals.coerce(
          given,
          field.type,
          path.key(field.name),
          depth + 1,
        ),
      );
    }
    return _absent(literal, type, field, (path, depth));
  }

  // The default of a field the literal does not give, or the error when it
  // is required.
  ({Object? value})? _absent(
    ObjectValue literal,
    InputObjectType type,
    InputValue field,
    (InputPath, int) place,
  ) {
    final (path, depth) = place;
    final fallback = field.defaultValue;
    if (fallback != null) {
      return (
        value: LiteralCoercion(
          environment,
          problems,
          const <String, Object?>{},
        ).coerce(fallback, field.type, path.key(field.name), depth + 1),
      );
    }
    if (_isRequired(field)) {
      final found = _printer.print(literal);
      return (
        value: _reject(
          _messages.missingField(type.name, field.name, found),
          path,
        ),
      );
    }
    return null;
  }

  bool _isRequired(InputValue field) =>
      field.type is NonNullType && field.defaultValue == null;

  // A `@oneOf` field needs a variable that has a non-null value.
  bool _isOneOfVariableBad(
    Variable variable,
    InputObjectType type,
    InputValue field,
    InputPath path,
  ) {
    final name = variable.name.value;
    final String? reason = !variables.containsKey(name)
        ? 'to provide a runtime value'
        : variables[name] == null
        ? 'not to be null'
        : null;
    if (reason == null) {
      return false;
    }
    problems.add(
      'Expected variable "\$$name" provided to field "${field.name}" for '
      'OneOf Input Object type "${type.name}" $reason.',
      path,
    );
    return true;
  }

  bool _checkUnknown(
    ObjectValue literal,
    InputObjectType type,
    InputPath path,
  ) {
    final names = [for (final field in type.fields) field.name];
    var isValid = true;
    for (final node in literal.fields) {
      if (names.contains(node.name.value)) {
        continue;
      }
      isValid = false;
      if (problems.hasOverflowed) {
        break;
      }
      problems.add(
        _messages.unknownField(
          type.name,
          node.name.value,
          names,
          _printer.print(literal),
        ),
        path,
      );
    }
    return isValid;
  }

  bool _checkOneOf(ObjectValue literal, InputObjectType type, InputPath path) {
    final names = {for (final field in type.fields) field.name};
    final known = [
      for (final node in literal.fields)
        if (names.contains(node.name.value)) node,
    ];
    if (known.length != 1) {
      problems.add(_messages.oneOf(type.name), path);
      return false;
    }
    if (known.first.value is NullValue) {
      problems.add(
        _messages.oneOf(type.name),
        path.key(known.first.name.value),
      );
      return false;
    }
    return true;
  }

  InvalidValue _reject(String message, InputPath path) {
    problems.add(message, path);
    return InvalidValue.instance;
  }
}
