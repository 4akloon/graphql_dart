import 'package:typed_graphql/typed_graphql.dart';

import '../coercion/coercion_environment.dart';
import '../coercion/conditional_directives.dart';
import 'defer_directive.dart';

/// What the collection of one plan node reads and never changes: the
/// fragments of the document, the values of the condition variables of the
/// request's [ConditionKey], and the readers of the directives.
final class PlanContext {
  /// Creates a context; [conditionValues] holds the booleans that exist.
  PlanContext(this.environment, this.fragments, this.conditionValues)
    : conditionals = ConditionalDirectives(environment),
      defers = DeferDirective(environment);

  /// The schema and the definitions.
  final CoercionEnvironment environment;

  /// The fragment definitions of the document by name.
  final Map<String, FragmentDefinition> fragments;

  /// The variables `@skip`, `@include` and `@defer` read, by name.
  final Map<String, Object?> conditionValues;

  /// Reads `@skip` and `@include`.
  final ConditionalDirectives conditionals;

  /// Reads `@defer`.
  final DeferDirective defers;

  /// The core schema.
  Schema get schema => environment.schema;
}
