import 'package:typed_graphql/typed_graphql.dart';

import 'argument_coercion.dart';
import 'coercion_environment.dart';
import 'coercion_result.dart';

/// Reads `@skip(if:)` and `@include(if:)` for field collection (spec
/// 6.3.2 `CollectFields`, graphql-js's `getDirectiveValues`): the `if`
/// arguments are coerced like any argument, with the built-in directive
/// definitions, so `@skip(if: $v)` with a missing required variable is an
/// error and not a guess.
final class ConditionalDirectives {
  /// Reads in [environment].
  ConditionalDirectives(this.environment)
    : _arguments = ArgumentCoercion(environment);

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  final ArgumentCoercion _arguments;

  /// Whether a selection written with [directives] is included: a
  /// [CoercionSuccess] holding a `bool`, or the failure of an `if` argument.
  /// `@skip(if: true)` and `@include(if: false)` exclude it.
  CoercionResult isIncluded(
    List<Directive> directives,
    Map<String, Object?> variables,
  ) {
    for (final (name, excludesWhen) in const [
      ('skip', true),
      ('include', false),
    ]) {
      final directive = _named(directives, name);
      if (directive == null) {
        continue;
      }
      switch (_condition(name, directive, variables)) {
        case CoercionSuccess(:final value) when value == excludesWhen:
          return const CoercionSuccess(false);
        case final CoercionFailure failure:
          return failure;
        case CoercionSuccess():
          break;
      }
    }
    return const CoercionSuccess(true);
  }

  Directive? _named(List<Directive> directives, String name) {
    for (final directive in directives) {
      if (directive.name.value == name) {
        return directive;
      }
    }
    return null;
  }

  // The value of the `if` argument, a `bool`.
  CoercionResult _condition(
    String name,
    Directive directive,
    Map<String, Object?> variables,
  ) {
    final definition = environment.schema.directiveNamed(name);
    if (definition == null) {
      throw StateError('The schema has no directive @$name.');
    }
    return switch (_arguments.coerce(
      '@$name',
      definition.arguments,
      directive.arguments,
      variables,
    )) {
      CoercionSuccess(value: final Map<String, Object?> values) =>
        CoercionSuccess(values['if']),
      CoercionSuccess() => throw StateError('Argument values are a map.'),
      final CoercionFailure failure => failure,
    };
  }
}
