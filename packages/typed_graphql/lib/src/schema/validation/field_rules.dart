import '../model/schema_field.dart';
import '../schema.dart';
import 'applied_directive_rules.dart';
import 'argument_rules.dart';
import 'name_rules.dart';
import 'type_reference_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the fields of an object or interface type (spec §3.6,
/// §3.7): unique and valid names, valid applied directives, known types,
/// and the rules of their arguments.
final class FieldRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of [fields], the fields of the type [typeName].
  void check(String typeName, List<SchemaField> fields) {
    UniqueNames(report).check(
      [for (final field in fields) (field.name, field.span)],
      .duplicateFieldName,
      (name) => 'Field "$typeName.$name" can only be defined once.',
    );
    for (final field in fields) {
      NameRules(report).check(field.name, field.span);
      AppliedDirectiveRules(
        report,
        schema,
      ).check(field.appliedDirectives, .fieldDefinition);
      TypeReferenceRules(report, schema).isKnownType(field.type, field.span);
      ArgumentRules(
        report,
        schema,
      ).check('$typeName.${field.name}', field.arguments);
    }
  }
}
