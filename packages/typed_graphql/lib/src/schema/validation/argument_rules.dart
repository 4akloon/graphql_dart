import '../model/input_value.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the arguments of one field or directive definition (spec
/// §3.6.1, §3.13): unique and valid names.
final class ArgumentRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rules.
  this;

  /// Reports the problems of [arguments], which belong to [owner]: the
  /// coordinate of a field (`Type.field`) or a directive (`@name`).
  void check(String owner, List<InputValue> arguments) {
    UniqueNames(report).check(
      [for (final argument in arguments) (argument.name, argument.span)],
      .duplicateArgumentName,
      (name) => 'Argument "$owner($name:)" can only be defined once.',
    );
    for (final argument in arguments) {
      NameRules(report).check(argument.name, argument.span);
    }
  }
}
