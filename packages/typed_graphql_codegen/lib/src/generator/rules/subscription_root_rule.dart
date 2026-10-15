import 'package:typed_graphql/typed_graphql.dart';

import '../../plan/root_typename.dart';

/// `GQL504`: a subscription whose root reads an abstract type would need
/// `__typename` at its root, which a subscription cannot select.
final class const SubscriptionRootRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _SubscriptionRoot(context);
}

final class _SubscriptionRoot(final ValidationContext context)
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

  void _check(OperationDefinition operation) {
    final found = RootTypename(
      context.schema,
      context.fragmentNamed,
    ).find(operation.selectionSet);
    if (found == null) return;
    final String what = found.fragmentName == null
        ? 'has an inline fragment on'
        : "spreads the fragment '${found.fragmentName}' on";
    context.report(
      .unsupportedInDocument,
      "The subscription '${operation.name?.value}' $what the abstract type "
      "'${found.typeName}' at its root, where '__typename' cannot be "
      'selected.',
      [found.selection],
    );
  }
}
