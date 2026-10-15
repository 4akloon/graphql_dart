import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Disables introspection (R3.5, `GQL235`): a field whose named output
/// type is an introspection type, such as `__schema` or `__type`, is an
/// error. `__typename` stays allowed.
///
/// A port of graphql-js's `NoSchemaIntrospectionCustomRule`. Disabling
/// introspection is not a best practice; use it only when it is needed. The
/// rule is opt-in: it is not one of the specified rules.
///
/// {@category validation}
final class const NoIntrospectionRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NoIntrospection(context);
}

final class _NoIntrospection(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is Field) {
      final type = context.typeInfo.type;
      // Names starting with "__" are reserved to the introspection types.
      if (type != null &&
          (context.schema.namedTypeOf(type)?.name.startsWith('__') ?? false)) {
        context.report(
          .introspectionDisabled,
          'GraphQL introspection has been disabled, but the requested query '
          'contained the field "${node.name.value}".',
          [node],
        );
      }
    }
    return .next;
  }
}
