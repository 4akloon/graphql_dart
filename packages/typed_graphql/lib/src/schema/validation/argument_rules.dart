import '../model/input_value.dart';
import '../schema.dart';
import 'applied_directive_rules.dart';
import 'name_rules.dart';
import 'type_reference_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the arguments of one field or directive definition (spec
/// §3.6.1, §3.13): unique and valid names, valid applied directives and
/// known types.
final class ArgumentRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
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
      AppliedDirectiveRules(
        report,
        schema,
      ).check(argument.appliedDirectives, .argumentDefinition);
      TypeReferenceRules(
        report,
        schema,
      ).isKnownType(argument.type, argument.span);
    }
  }
}
