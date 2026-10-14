import '../diagnostics/diagnostic_code.dart';
import '../language/ast/node.dart';
import '../language/ast/value.dart';
import '../language/visitor/ast_visitor.dart';
import '../language/visitor/visit_action.dart';
import '../schema/validation/value_checker.dart';
import '../schema/validation/value_problem_kind.dart';
import 'validation_context.dart';

/// The visitor behind the three value rules (spec §5.6): graphql-js's
/// `ValuesOfCorrectTypeRule` checks each value literal once, and M4 splits
/// its errors by [kind], each reported with [code].
///
/// On entering a literal whose input type is known it checks the whole
/// value and skips its children, as graphql-js does.
final class ValueProblemVisitor(
  /// The context of the run.
  final ValidationContext context,

  /// The problems this rule reports.
  final ValueProblemKind kind,

  /// The code of those problems.
  final DiagnosticCode code,
) extends AstVisitor {
  /// Creates the visitor.
  this;

  @override
  VisitAction enter(Node node) {
    if (node is! Value || node is Variable) {
      return .next;
    }
    // A list's own type is its parent's input type: TypeInfo has already
    // entered the item type.
    final type = node is ListValue
        ? context.typeInfo.parentInputType
        : context.typeInfo.inputType;
    if (type == null) {
      return .skip;
    }
    final checker = ValueChecker(
      context.schema,
      allowsVariables: true,
      includesSuggestions: context.includesSuggestions,
    );
    for (final problem in checker.check(node, type)) {
      if (problem.kind == kind) {
        context.report(code, problem.message, [problem.node]);
      }
    }
    return .skip;
  }
}
