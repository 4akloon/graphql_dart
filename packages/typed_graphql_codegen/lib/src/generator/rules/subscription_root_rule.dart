import 'package:typed_graphql/typed_graphql.dart';

import '../../plan/root_typename.dart';

/// `GQL504`: a subscription whose root spreads a fragment that plans as a
/// sealed class would need `__typename` at its root, which a subscription
/// cannot select.
final class const SubscriptionRootRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) => _SubscriptionRoot(
    context,
    RootTypename(context.schema, {
      for (final definition in context.document.definitions)
        if (definition is FragmentDefinition) definition.name.value: definition,
    }),
  );
}

final class _SubscriptionRoot(
  final ValidationContext context,
  final RootTypename rootTypename,
) extends AstVisitor {
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

  // An anonymous subscription is a GQL503 already.
  void _check(OperationDefinition operation) {
    final String? name = operation.name?.value;
    final found = rootTypename.find(operation.selectionSet);
    if (name == null || found == null) return;
    final String where = switch (found.selection) {
      FragmentSpread(:final name) => "spreads '...${name.value}' at its root",
      _ => 'has an inline fragment at its root',
    };
    context.report(
      .unsupportedInDocument,
      "The subscription '$name' $where, which reads the fragment "
      "'${found.fragmentName}' on the abstract type '${found.typeName}'; the "
      "root would need '__typename', which a subscription cannot select.",
      [found.selection],
    );
  }
}
