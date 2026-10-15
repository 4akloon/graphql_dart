import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.2.1.1 "Operation Type Existence": the schema has a root type for
/// the operation's type (`GQL201`).
///
/// {@category validation}
final class const KnownOperationTypesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _KnownOperationTypes(context);
}

final class _KnownOperationTypes(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case OperationDefinition(:final operation)
        when context.schema.rootTypeName(operation) == null) {
      context.report(
        .knownOperationTypes,
        'The ${operation.name} operation is not supported by the schema.',
        [node],
      );
    }
    return .next;
  }
}
