import '../../diagnostics/diagnostic_code.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'limit_visitor.dart';
import 'operation_subject.dart';
import 'selection_measure.dart';

/// Limits the depth of an operation (R3.5, `GQL232`).
///
/// A field directly in the operation has depth 1, a field in its selection
/// set depth 2, and so on; inline fragments and fragment spreads add no
/// depth, and a spread counts as if its fragment were written there.
/// Introspection fields count like any field. The rule is opt-in: it is
/// not one of the specified rules.
///
/// {@category validation}
final class const MaxDepthRule({
  /// The deepest field an operation may have.
  required final int maxDepth,
}) extends ValidationRule {
  /// Creates the rule.
  this;

  /// Throws a [RangeError] when [maxDepth] is negative.
  @override
  AstVisitor createVisitor(ValidationContext context) {
    RangeError.checkNotNegative(maxDepth, 'maxDepth');
    return _MaxDepth(context, SelectionMeasure(context, .depth, maxDepth));
  }
}

final class _MaxDepth extends LimitVisitor {
  _MaxDepth(super.context, super.measure);

  @override
  DiagnosticCode get code => .maxDepthExceeded;

  @override
  String message(OperationDefinition operation, int value) =>
      '${OperationSubject(operation).text} has a depth of $value, more than '
      'the maximum of ${measure.limit}.';
}
