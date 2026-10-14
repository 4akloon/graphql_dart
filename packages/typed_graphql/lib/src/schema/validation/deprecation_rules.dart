import '../../language/ast/type_ref.dart';
import '../model/input_value.dart';
import 'node_span.dart';
import 'validation_report.dart';

/// The rule that a required argument or input field is not deprecated
/// (spec §3.6.1, §3.10): a caller must give it, so it cannot go away.
final class DeprecationRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rule.
  this;

  /// Reports [input] when it is required (non-null without a default)
  /// and deprecated; [subject] names it, as `Required argument Q.f(a:)`.
  void checkRequired(String subject, InputValue input) {
    if (input.type is! NonNullType ||
        input.defaultValue != null ||
        input.deprecationReason == null) {
      return;
    }
    final deprecated = input.appliedDirectives
        .where((directive) => directive.name == 'deprecated')
        .first;
    report.error(.deprecatedRequiredInput, '$subject cannot be deprecated.', [
      deprecated.span,
      const NodeSpan().within(input.span, input.type),
    ]);
  }
}
