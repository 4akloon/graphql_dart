import '../../diagnostics/diagnostic_code.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'limit_visitor.dart';
import 'operation_subject.dart';
import 'selection_measure.dart';

/// Limits the aliases of an operation (R3.5, `GQL233`).
///
/// Counts the fields written with an alias; each spread counts the aliases
/// of its fragment again. The rule is opt-in: it is not one of the
/// specified rules.
///
/// {@category validation}
final class const MaxAliasesRule({
  /// The most aliases an operation may have.
  required final int maxAliases,
}) extends ValidationRule {
  /// Creates the rule.
  this;

  /// Throws a [RangeError] when [maxAliases] is negative.
  @override
  AstVisitor createVisitor(ValidationContext context) {
    RangeError.checkNotNegative(maxAliases, 'maxAliases');
    return _MaxAliases(
      context,
      SelectionMeasure(context, .aliases, maxAliases),
    );
  }
}

final class _MaxAliases extends LimitVisitor {
  _MaxAliases(super.context, super.measure);

  @override
  DiagnosticCode get code => .maxAliasesExceeded;

  @override
  String message(OperationDefinition operation, int value) =>
      '${OperationSubject(operation).text} has more than ${measure.limit} '
      'aliases.';
}
