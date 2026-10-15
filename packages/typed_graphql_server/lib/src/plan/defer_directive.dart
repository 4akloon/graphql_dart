import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/argument_coercion.dart';
import '../coercion/coercion_environment.dart';
import '../coercion/coercion_result.dart';

/// Reads `@defer(if:)` during field collection. `@defer` runs inline in M5
/// (spec section 18), so the plan only records which fields a deferred
/// fragment holds.
final class DeferDirective {
  /// Reads in [environment].
  DeferDirective(this.environment) : _arguments = ArgumentCoercion(environment);

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  final ArgumentCoercion _arguments;

  /// Whether a fragment written with [directives] is deferred: a
  /// [CoercionSuccess] holding a `bool`, or the failure of an argument. A
  /// schema without `@defer` defers nothing, and `if` defaults to true.
  CoercionResult isDeferred(
    List<Directive> directives,
    Map<String, Object?> variables,
  ) {
    final definition = environment.schema.directiveNamed('defer');
    if (definition == null) {
      return const CoercionSuccess(false);
    }
    for (final directive in directives) {
      if (directive.name.value != 'defer') {
        continue;
      }
      return switch (_arguments.coerce(
        '@defer',
        definition.arguments,
        directive.arguments,
        variables,
      )) {
        CoercionSuccess(value: final Map<String, Object?> values) =>
          CoercionSuccess(values['if'] != false),
        CoercionSuccess() => throw StateError('Argument values are a map.'),
        final CoercionFailure failure => failure,
      };
    }
    return const CoercionSuccess(false);
  }
}
