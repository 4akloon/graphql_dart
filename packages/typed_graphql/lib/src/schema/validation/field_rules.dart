import '../model/schema_field.dart';
import 'argument_rules.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of the fields of an object or interface type (spec §3.6,
/// §3.7): unique and valid names, and their arguments'.
final class FieldRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rules.
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
      ArgumentRules(report).check('$typeName.${field.name}', field.arguments);
    }
  }
}
