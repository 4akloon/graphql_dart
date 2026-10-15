import 'package:typed_graphql/typed_graphql.dart';

/// `GQL503`: every operation has a name, because the generated classes are
/// named after it.
final class const NamedOperationsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NamedOperations(context);
}

final class _NamedOperations(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition(name: null):
        context.report(
          .anonymousOperation,
          'An operation needs a name: its classes are named after it.',
          [node],
        );
        return .skip;
      case ExecutableDefinition():
        return .skip;
      default:
        return .next;
    }
  }
}
