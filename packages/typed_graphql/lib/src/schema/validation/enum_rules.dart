import '../model/schema_type.dart';
import '../schema.dart';
import 'applied_directive_rules.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of an enum type (spec §3.9): unique and valid value names
/// and valid applied directives.
final class EnumRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of [type].
  void check(EnumType type) {
    UniqueNames(report).check(
      [for (final value in type.values) (value.name, value.span)],
      .duplicateEnumValueName,
      (name) => 'Enum value "${type.name}.$name" can only be defined once.',
    );
    for (final value in type.values) {
      NameRules(report).checkEnumValue(value.name, value.span);
      AppliedDirectiveRules(
        report,
        schema,
      ).check(value.appliedDirectives, .enumValue);
    }
  }
}
