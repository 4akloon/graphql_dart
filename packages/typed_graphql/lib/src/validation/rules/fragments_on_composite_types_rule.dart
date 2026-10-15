import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/type_ref.dart';
import '../../language/printer/printer.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.1.3 "Fragments On Composite Types": a fragment's type
/// condition is an object, interface or union type (`GQL213`).
///
/// An unknown type is left to `KnownTypeNamesRule`.
///
/// {@category validation}
final class const FragmentsOnCompositeTypesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _FragmentsOnCompositeTypes(context);
}

final class _FragmentsOnCompositeTypes(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case InlineFragment(:final typeCondition?):
        if (_isNonComposite(typeCondition)) {
          context.report(
            .fragmentsOnCompositeTypes,
            'Fragment cannot condition on non composite type '
            '"${const Printer().print(typeCondition)}".',
            [typeCondition],
          );
        }
      case FragmentDefinition(:final name, :final typeCondition):
        if (_isNonComposite(typeCondition)) {
          context.report(
            .fragmentsOnCompositeTypes,
            'Fragment "${name.value}" cannot condition on non composite type '
            '"${const Printer().print(typeCondition)}".',
            [typeCondition],
          );
        }
      default:
    }
    return .next;
  }

  bool _isNonComposite(NamedType condition) =>
      switch (context.schema.namedTypeOf(condition)) {
        final type? => !type.isCompositeType,
        null => false,
      };
}
