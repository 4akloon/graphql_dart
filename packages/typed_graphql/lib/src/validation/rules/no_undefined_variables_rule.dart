import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'operation_visitor.dart';

/// Spec §5.8.3 "All Variable Uses Defined": every variable an operation
/// uses, directly or through fragments, is declared by it (`GQL227`).
///
/// Reported when the walk leaves the document, operation by operation.
///
/// {@category validation}
final class const NoUndefinedVariablesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NoUndefinedVariables(context);
}

final class _NoUndefinedVariables(final ValidationContext context)
    extends OperationVisitor {
  @override
  void checkOperation(OperationDefinition operation) {
    final declared = {
      for (final definition in operation.variableDefinitions)
        definition.variable.name.value,
    };
    final operationName = operation.name?.value;
    for (final usage in context.recursiveVariableUsages(operation)) {
      final name = usage.node.name.value;
      if (declared.contains(name)) {
        continue;
      }
      context.report(
        .noUndefinedVariables,
        operationName == null
            ? 'Variable "\$$name" is not defined.'
            : 'Variable "\$$name" is not defined by operation '
                  '"$operationName".',
        [usage.node, operation],
      );
    }
  }
}
