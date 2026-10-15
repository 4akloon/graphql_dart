import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'operation_visitor.dart';

/// Spec §5.8.4 "All Variables Used": every variable an operation declares
/// is used by it, directly or through fragments (`GQL228`).
///
/// Reported when the walk leaves the document, operation by operation.
///
/// {@category validation}
final class const NoUnusedVariablesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NoUnusedVariables(context);
}

final class _NoUnusedVariables(final ValidationContext context)
    extends OperationVisitor {
  @override
  void checkOperation(OperationDefinition operation) {
    // Every report after the error limit or the budget is ignored.
    if (context.isAborted) {
      return;
    }
    final used = {
      for (final usage in context.recursiveVariableUsages(operation))
        usage.node.name.value,
    };
    final operationName = operation.name?.value;
    for (final definition in operation.variableDefinitions) {
      if (context.isAborted) {
        return;
      }
      final name = definition.variable.name.value;
      if (used.contains(name)) {
        continue;
      }
      context.report(
        .noUnusedVariables,
        operationName == null
            ? 'Variable "\$$name" is never used.'
            : 'Variable "\$$name" is never used in operation '
                  '"$operationName".',
        [definition],
      );
    }
  }
}
