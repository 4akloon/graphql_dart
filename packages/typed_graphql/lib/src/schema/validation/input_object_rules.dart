import '../model/schema_type.dart';
import '../schema.dart';
import 'applied_directive_rules.dart';
import 'name_rules.dart';
import 'type_reference_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of an input object type (spec §3.10): unique and valid
/// field names, valid applied directives and known field types.
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
      TypeReferenceRules(report, schema).isKnownType(field.type, field.span);
    }
  }
}
