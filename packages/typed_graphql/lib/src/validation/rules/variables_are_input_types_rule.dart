import '../../language/ast/node.dart';
import '../../language/ast/variable_definition.dart';
import '../../language/printer/printer.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.8.2 "Variables Are Input Types": a variable's type is a
/// scalar, enum or input object type, possibly wrapped (`GQL226`).
///
/// An unknown type is left to `KnownTypeNamesRule`.
///
/// {@category validation}
final class const VariablesAreInputTypesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _VariablesAreInputTypes(context);
}

final class _VariablesAreInputTypes(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case VariableDefinition(:final variable, :final type)) {
      final named = context.schema.namedTypeOf(type);
      if (named != null && !named.isInputType) {
        context.report(
          .variablesAreInputTypes,
          'Variable "\$${variable.name.value}" cannot be non-input type '
          '"${const Printer().print(type)}".',
          [type],
        );
      }
    }
    return .next;
  }
}
