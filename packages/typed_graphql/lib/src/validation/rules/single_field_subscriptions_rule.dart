import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'subscription_fields.dart';

/// Spec §5.2.4.1 "Single Root Field": a subscription selects one
/// top-level field, not an introspection field, without `@skip` or
/// `@include` at the top level (`GQL204`).
///
/// {@category validation}
final class const SingleFieldSubscriptionsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _SingleFieldSubscriptions(context);
}

final class _SingleFieldSubscriptions(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition(operation: .subscription):
        _check(node);
        return .skip;
      case ExecutableDefinition():
        return .skip;
      default:
        return .next;
    }
  }

  ObjectType? get _root => switch (context.schema.rootTypeName(
    .subscription,
  )) {
    final name? => switch (context.schema.typeNamed(name)) {
      final ObjectType type => type,
      _ => null,
    },
    null => null,
  };

  void _check(OperationDefinition operation) {
    final root = _root;
    if (root == null) {
      return;
    }
    final collected = SubscriptionFields(context, root, operation.selectionSet);
    final subject = switch (operation.name) {
      final name? => 'Subscription "${name.value}"',
      null => 'Anonymous Subscription',
    };
    if (collected.forbiddenDirectives.isNotEmpty) {
      context.report(
        .singleFieldSubscriptions,
        '$subject must not use `@skip` or `@include` directives in the top '
        'level selection.',
        collected.forbiddenDirectives,
      );
      return;
    }
    final groups = collected.fields.values.toList();
    if (groups.length > 1) {
      context.report(
        .singleFieldSubscriptions,
        '$subject must select only one top level field.',
        [for (final group in groups.skip(1)) ...group],
      );
    }
    for (final group in groups) {
      if (group.first.name.value.startsWith('__')) {
        context.report(
          .singleFieldSubscriptions,
          '$subject must not select an introspection top level field.',
          group,
        );
      }
    }
  }
}
