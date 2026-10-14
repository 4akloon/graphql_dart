import '../model/schema_type.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of an input object type (spec §3.10): unique and valid
/// field names.
final class InputObjectRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rules.
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
    }
  }
}
