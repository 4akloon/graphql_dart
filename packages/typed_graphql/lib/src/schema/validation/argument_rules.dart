import '../../language/printer/printer.dart';
import '../model/input_value.dart';
import '../schema.dart';
import 'applied_directive_rules.dart';
import 'default_value_rules.dart';
import 'deprecation_rules.dart';
import 'name_rules.dart';
import 'node_span.dart';
import 'type_reference_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the arguments of one field or directive definition (spec
/// §3.6.1, §3.13): unique and valid names, valid applied directives,
/// known input types, no deprecated required argument and valid default
/// values.
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
      final coordinate = '$owner(${argument.name}:)';
      NameRules(report).check(argument.name, argument.span);
      AppliedDirectiveRules(
        report,
        schema,
      ).check(argument.appliedDirectives, .argumentDefinition);
      _type(coordinate, argument, isOfDirective: owner.startsWith('@'));
      DeprecationRules(
        report,
      ).checkRequired('Required argument $coordinate', argument);
      DefaultValueRules(report, schema).check(coordinate, argument);
    }
  }

  // graphql-js points at a directive argument, but at a field argument's
  // type.
  void _type(
    String coordinate,
    InputValue argument, {
    required bool isOfDirective,
  }) {
    if (!TypeReferenceRules(
          report,
          schema,
        ).isKnownType(argument.type, argument.span) ||
        schema.isInputType(argument.type)) {
      return;
    }
    final span = isOfDirective
        ? argument.span
        : const NodeSpan().within(argument.span, argument.type);
    report.error(
      .notInputType,
      'The type of $coordinate must be Input Type but got: '
      '${const Printer().print(argument.type)}.',
      [span],
    );
  }
}
