import '../model/schema_type.dart';
import '../schema.dart';
import 'type_reference_rules.dart';
import 'validation_report.dart';

/// The rules of a union type (spec §3.8), as graphql-js's
/// `validateUnionMembers`: one or more members, each a known object type
/// named once.
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
    if (type.memberTypes.isEmpty) {
      report.error(
        .missingUnionMembers,
        'Union type ${type.name} must define one or more member types.',
        [type.span],
      );
    }
    final included = <String>{};
    for (final member in type.memberTypes) {
      if (!TypeReferenceRules(
        report,
        schema,
      ).isKnown(member.name, member.span)) {
        continue;
      }
      final spans = [
        for (final reference in type.memberTypes)
          if (reference.name == member.name) reference.span,
      ];
      if (!included.add(member.name)) {
        report.error(
          .repeatedUnionMember,
          'Union type ${type.name} can only include type ${member.name} '
          'once.',
          spans,
        );
      } else if (schema.typeNamed(member.name) is! ObjectType) {
        report.error(
          .nonObjectUnionMember,
          'Union type ${type.name} can only include Object types, it cannot '
          'include ${member.name}.',
          spans,
        );
      }
    }
  }
}
