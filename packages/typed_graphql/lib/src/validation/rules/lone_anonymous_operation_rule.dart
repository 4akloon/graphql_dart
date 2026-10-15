import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.2.3.1 "Lone Anonymous Operation": an anonymous operation is the
/// only operation of its document (`GQL203`).
///
/// {@category validation}
final class const LoneAnonymousOperationRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _LoneAnonymousOperation(context);
}

final class _LoneAnonymousOperation(final ValidationContext context)
    extends AstVisitor {
  int _operationCount = 0;

  // Reported at each operation, not at the document, so the errors of all
  // rules keep graphql-js's order.
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case Document(:final definitions):
        _operationCount = definitions.whereType<OperationDefinition>().length;
        return .next;
      case OperationDefinition(name: null) when _operationCount > 1:
        context.report(
          .loneAnonymousOperation,
          'This anonymous operation must be the only defined operation.',
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
