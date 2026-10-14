import '../../language/printer/printer.dart';
import '../model/schema_field.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'applied_directive_rules.dart';
import 'argument_rules.dart';
import 'name_rules.dart';
import 'node_span.dart';
import 'type_reference_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the fields of an object or interface type (spec §3.6,
/// §3.7), as graphql-js's `validateFields`: at least one field; unique and
/// valid names, valid applied directives, known output types, and the
/// rules of their arguments.
final class FieldRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of [fields], the fields of [type].
  void check(SchemaType type, List<SchemaField> fields) {
    if (fields.isEmpty) {
      report.error(
        .missingFields,
        'Type ${type.name} must define one or more fields.',
        [type.span],
      );
    }
    UniqueNames(report).check(
      [for (final field in fields) (field.name, field.span)],
      .duplicateFieldName,
      (name) => 'Field "${type.name}.$name" can only be defined once.',
    );
    for (final field in fields) {
      NameRules(report).check(field.name, field.span);
      AppliedDirectiveRules(
        report,
        schema,
      ).check(field.appliedDirectives, .fieldDefinition);
      _type('${type.name}.${field.name}', field);
      ArgumentRules(
        report,
        schema,
      ).check(
        '${type.name}.${field.name}',
        field.arguments,
        isOfDirective: false,
      );
    }
  }

  void _type(String coordinate, SchemaField field) {
    if (!TypeReferenceRules(
          report,
          schema,
        ).isKnownType(field.type, field.span) ||
        schema.isOutputType(field.type)) {
      return;
    }
    report.error(
      .notOutputType,
      'The type of $coordinate must be Output Type but got: '
      '${const Printer().print(field.type)}.',
      [const NodeSpan().within(field.span, field.type)],
    );
  }
}
