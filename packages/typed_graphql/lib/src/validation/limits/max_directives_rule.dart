import '../../diagnostics/diagnostic_code.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'limit_visitor.dart';
import 'operation_subject.dart';
import 'selection_measure.dart';

/// Limits the directives of an operation (R3.5, `GQL234`).
///
/// Counts the directives on the operation, its variable definitions, its
/// fields, inline fragments and spreads; each spread also counts the
/// directives of its fragment's definition and of its content again. The
/// rule is opt-in: it is not one of the specified rules.
///
/// {@category validation}
final class const MaxDirectivesRule({
  /// The most directives an operation may have.
  required final int maxDirectives,
}) extends ValidationRule {
  /// Creates the rule.
  this;

  /// Throws a [RangeError] when [maxDirectives] is negative.
  @override
  AstVisitor createVisitor(ValidationContext context) {
    RangeError.checkNotNegative(maxDirectives, 'maxDirectives');
    return _MaxDirectives(
      context,
      SelectionMeasure(context, .directives, maxDirectives),
    );
  }
}

final class _MaxDirectives extends LimitVisitor {
  _MaxDirectives(super.context, super.measure);

  @override
  DiagnosticCode get code => .maxDirectivesExceeded;

  @override
  String message(OperationDefinition operation, int value) =>
      '${OperationSubject(operation).text} has more than ${measure.limit} '
      'directives.';
}
