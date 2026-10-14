import '../model/input_value.dart';
import '../schema.dart';
import 'node_span.dart';
import 'validation_report.dart';
import 'value_checker.dart';

/// The rule that the default value of an argument or an input field is a
/// value of its type (spec §3.6.1, §3.10), as graphql-js's
/// `validateDefaultValue` for a literal default.
final class DefaultValueRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rule for [schema].
  this;

  /// Reports each problem of the default value of [input], whose
  /// coordinate is [coordinate] (`Type.field(arg:)`, `@d(arg:)`,
  /// `Input.field`), at the node it is about.
  void check(String coordinate, InputValue input) {
    final value = input.defaultValue;
    if (value == null) {
      return;
    }
    for (final problem in ValueChecker(schema).check(value, input.type)) {
      report.error(
        .invalidDefaultValue,
        '$coordinate has invalid default value${problem.pathText}: '
        '${problem.message}',
        [const NodeSpan().within(input.span, problem.node)],
      );
    }
  }
}
