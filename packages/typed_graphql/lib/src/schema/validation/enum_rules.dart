import '../model/schema_type.dart';
import 'name_rules.dart';
import 'unique_names.dart';
import 'validation_report.dart';

/// The rules of an enum type (spec §3.9): unique and valid value names.
final class EnumRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rules.
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
    }
  }
}
