import 'package:typed_graphql/typed_graphql.dart';

import '../builder/enum_type_def.dart';
import '../builder/scalar_type_def.dart';
import 'coercion_environment.dart';
import 'coercion_problems.dart';
import 'input_path.dart';
import 'invalid_value.dart';
import 'value_inspector.dart';

/// Coerces a JSON value to a scalar or an enum value (spec 3.5, 3.9) with
/// graphql-js's messages. A problem is recorded in [problems]; the result
/// is then [InvalidValue.instance].
final class LeafCoercion {
  /// Coerces into [problems].
  LeafCoercion(this.environment, this.problems);

  static const ValueInspector _inspector = ValueInspector();
  static const Suggestions _suggestions = Suggestions();

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// Where problems go.
  final CoercionProblems problems;

  /// The Dart value of [value] for the leaf [type] at [path].
  Object? coerce(JsonValue value, SchemaType type, InputPath path) =>
      switch (type) {
        ScalarType() => _scalar(value, type, path),
        EnumType() => _enum(value, type, path),
        _ => _reject('Type "${type.name}" is not a leaf type.', path),
      };

  Object _reject(String message, InputPath path, {DiagnosticCode? code}) {
    problems.add(message, path, code: code);
    return InvalidValue.instance;
  }

  ScalarCodec<Object>? _codecOf(String name) =>
      switch (environment.bindings.leaves[name]) {
        ScalarTypeDef<Object>(:final codec) => codec,
        _ => const ScalarCodecs().codecFor(name),
      };

  Object? _scalar(JsonValue value, ScalarType type, InputPath path) {
    final codec = _codecOf(type.name);
    if (codec == null) {
      return _reject(
        'Scalar "${type.name}" has no codec to read input with.',
        path,
        code: DiagnosticCode.unexpectedError,
      );
    }
    final DecodeResult<Object> result;
    try {
      result = codec.decode(value);
    } on Object catch (error, stackTrace) {
      problems.add(
        'Unexpected error.',
        path,
        code: DiagnosticCode.unexpectedError,
        thrown: (error: error, stackTrace: stackTrace),
      );
      return InvalidValue.instance;
    }
    return switch (result) {
      DecodeSuccess(:final value) => value,
      DecodeFailure(:final message) => _reject(message, path),
    };
  }

  Object? _enum(JsonValue value, EnumType type, InputPath path) {
    final definition = environment.bindings.leaves[type.name];
    if (definition is! EnumTypeDef<Enum>) {
      return _reject('Enum "${type.name}" has no definition.', path);
    }
    if (value is! JsonString) {
      final printed = _inspector.inspect(value);
      return _reject(
        'Enum "${type.name}" cannot represent non-string value: $printed.'
        '${suggestEnumValue(printed, type)}',
        path,
      );
    }
    return definition.valueNamed(value.value) ??
        _reject(
          'Value "${value.value}" does not exist in "${type.name}" enum.'
          '${suggestEnumValue(value.value, type)}',
          path,
        );
  }

  /// graphql-js's "Did you mean the enum value ..." text for [input], empty
  /// when suggestions are off.
  String suggestEnumValue(String input, EnumType type) {
    if (!environment.includesSuggestions) {
      return '';
    }
    final names = [for (final value in type.values) value.name];
    return _suggestions.didYouMean(
      _suggestions.listFor(input, names),
      subject: 'the enum value',
    );
  }
}
