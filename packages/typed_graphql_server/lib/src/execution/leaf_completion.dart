import 'package:typed_graphql/typed_graphql.dart';

import '../builder/enum_type_def.dart';
import '../builder/scalar_type_def.dart';
import '../coercion/value_inspector.dart';
import 'completion_site.dart';
import 'execution_run.dart';

/// Completes the value of a scalar or an enum (September2025 6.4.3, "Result
/// Coercion"): the Int range, Float finiteness, the enum's names, the codec's
/// `encode`; the messages are graphql-js's.
final class LeafCompletion {
  /// Completes for [_run].
  LeafCompletion(this._run);

  static const ValueInspector _inspector = ValueInspector();

  final ExecutionRun _run;

  /// The JSON of [value] for the leaf [type], or null after reporting why
  /// the value cannot be written.
  JsonValue? complete(SchemaType type, Object value, CompletionSite site) {
    try {
      return switch (type) {
        ScalarType() => _scalar(type, value),
        EnumType() => _enum(type, value),
        _ => throw StateError('"${type.name}" is not a leaf type.'),
      };
    } on _Unrepresentable catch (problem) {
      _run.reporter.fieldError(
        DiagnosticCode.unserializableValue,
        problem.message,
        site,
      );
    } on Object catch (error, stackTrace) {
      if (error is ArgumentError) {
        _run.reporter.fieldError(
          DiagnosticCode.unserializableValue,
          '${error.message}',
          site,
        );
      } else {
        _run.reporter.thrown(error, stackTrace, site);
      }
    }
    return null;
  }

  JsonValue _scalar(ScalarType type, Object value) {
    switch (type.name) {
      case 'Int':
        return _int(value);
      case 'Float':
        return _float(value);
    }
    final codec = switch (_run.bindings.leaves[type.name]) {
      ScalarTypeDef<Object>(:final codec) => codec,
      _ => const ScalarCodecs().codecFor(type.name),
    };
    if (codec == null) {
      throw StateError('Scalar "${type.name}" has no codec.');
    }
    return codec.encode(value);
  }

  JsonValue _int(Object value) {
    if (value is! int) {
      throw _Unrepresentable(
        'Int cannot represent non-integer value: ${_inspector.inspect(value)}',
      );
    }
    if (value < -2147483648 || value > 2147483647) {
      throw _Unrepresentable(
        'Int cannot represent non 32-bit signed integer value: $value',
      );
    }
    return JsonNumber(value);
  }

  JsonValue _float(Object value) {
    if (value is! num || !value.isFinite) {
      throw _Unrepresentable(
        'Float cannot represent non numeric value: '
        '${_inspector.inspect(value)}',
      );
    }
    return JsonNumber(value);
  }

  JsonValue _enum(EnumType type, Object value) {
    final definition = _run.bindings.leaves[type.name];
    try {
      if (definition is EnumTypeDef<Enum>) {
        return JsonString(definition.nameOf(value as Enum));
      }
    } on Object {
      // Not a value of the enum: the message below says so.
    }
    throw _Unrepresentable(
      'Enum "${type.name}" cannot represent value: '
      '${_inspector.inspect(value)}',
    );
  }
}

class _Unrepresentable implements Exception {
  _Unrepresentable(this.message);

  final String message;
}
