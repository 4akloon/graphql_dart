import '../../language/ast/type_ref.dart';
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

/// The rules of an input object type (spec §3.10): one or more fields,
/// unique and valid field names, valid applied directives, known input
/// types, no deprecated required field, valid default values and, for a
/// `@oneOf` type, nullable fields without defaults.
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
    if (type.fields.isEmpty) {
      report.error(
        .missingInputFields,
        'Input Object type ${type.name} must define one or more fields.',
        [type.span],
      );
    }
    UniqueNames(report).check(
      [for (final field in type.fields) (field.name, field.span)],
      .duplicateFieldName,
      (name) => 'Field "${type.name}.$name" can only be defined once.',
    );
    for (final field in type.fields) {
      _field(type, field);
    }
  }

  void _field(InputObjectType type, InputValue field) {
    final coordinate = '${type.name}.${field.name}';
    NameRules(report).check(field.name, field.span);
    AppliedDirectiveRules(
      report,
      schema,
    ).check(field.appliedDirectives, .inputFieldDefinition);
    _type(coordinate, field);
    DeprecationRules(
      report,
    ).checkRequired('Required input field $coordinate', field);
    DefaultValueRules(report, schema).check(coordinate, field);
    if (type.isOneOf) {
      _oneOf(coordinate, field);
    }
  }

  // Spec §3.10.1: exactly one field of a OneOf value is given, so none can
  // be required or defaulted.
  void _oneOf(String coordinate, InputValue field) {
    if (field.type is NonNullType) {
      report.error(
        .nonNullOneOfField,
        'OneOf input field $coordinate must be nullable.',
        [const NodeSpan().within(field.span, field.type)],
      );
    }
    if (field.defaultValue != null) {
      report.error(
        .defaultedOneOfField,
        'OneOf input field $coordinate cannot have a default value.',
        [field.span],
      );
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
