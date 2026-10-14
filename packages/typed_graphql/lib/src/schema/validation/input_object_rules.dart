import '../../language/printer/printer.dart';
import '../model/input_value.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'applied_directive_rules.dart';
import 'default_value_rules.dart';
import 'deprecation_rules.dart';
import 'name_rules.dart';
import 'node_span.dart';
import 'type_reference_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of an input object type (spec §3.10): unique and valid
/// field names, valid applied directives, known input types, no
/// deprecated required field and valid default values.
final class InputObjectRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of [type].
  void check(InputObjectType type) {
    UniqueNames(report).check(
      [for (final field in type.fields) (field.name, field.span)],
      .duplicateFieldName,
      (name) => 'Field "${type.name}.$name" can only be defined once.',
    );
    for (final field in type.fields) {
      NameRules(report).check(field.name, field.span);
      AppliedDirectiveRules(
        report,
        schema,
      ).check(field.appliedDirectives, .inputFieldDefinition);
      _type('${type.name}.${field.name}', field);
      DeprecationRules(
        report,
      ).checkRequired('Required input field ${type.name}.${field.name}', field);
      DefaultValueRules(
        report,
        schema,
      ).check('${type.name}.${field.name}', field);
    }
  }

  void _type(String coordinate, InputValue field) {
    if (!TypeReferenceRules(
          report,
          schema,
        ).isKnownType(field.type, field.span) ||
        schema.isInputType(field.type)) {
      return;
    }
    report.error(
      .notInputType,
      'The type of $coordinate must be Input Type but got: '
      '${const Printer().print(field.type)}.',
      [const NodeSpan().within(field.span, field.type)],
    );
  }
}
