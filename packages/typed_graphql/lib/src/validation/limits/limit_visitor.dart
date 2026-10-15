import '../../diagnostics/diagnostic_code.dart';
import '../../language/ast/executable_definition.dart';
import '../rules/operation_visitor.dart';
import '../validation_context.dart';
import 'selection_measure.dart';

/// The visitor of a limit rule: measures each operation and reports it at
/// most once, at the operation, when it is over the limit.
abstract base class LimitVisitor(
  final ValidationContext context,
  final SelectionMeasure measure,
) extends OperationVisitor {
  /// Creates the visitor of a rule that measures with [measure].
  this;

  /// The code of the report.
  DiagnosticCode get code;

  /// The message for [operation], whose measured [value] is over the limit.
  String message(OperationDefinition operation, int value);

  @override
  void checkOperation(OperationDefinition operation) {
    final value = measure.measure(operation);
    if (value != null && value > measure.limit) {
      context.report(code, message(operation, value), [operation]);
    }
  }
}
