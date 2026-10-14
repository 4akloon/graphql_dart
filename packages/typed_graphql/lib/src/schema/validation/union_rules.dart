import '../model/schema_type.dart';
import '../schema.dart';
import 'type_reference_rules.dart';
import 'validation_report.dart';

/// The rules of a union type (spec §3.8): each member names a known type.
final class UnionRules(
  /// Receives the errors.
  final ValidationReport report,

  /// The schema checked.
  final Schema schema,
) {
  /// Creates the rules for [schema].
  this;

  /// Reports the problems of [type].
  void check(UnionType type) {
    for (final member in type.memberTypes) {
      TypeReferenceRules(report, schema).isKnown(member.name, member.span);
    }
  }
}
