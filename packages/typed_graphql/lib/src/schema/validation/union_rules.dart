import '../../diagnostics/source_span.dart';
import '../model/named_type_reference.dart';
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
    // One pass over the members; the places of a name are only needed by
    // the errors, and a union of M repeats must not cost M times M.
    final places = <String, List<SourceSpan?>>{};
    for (final member in type.memberTypes) {
      (places[member.name] ??= []).add(member.span);
    }
    for (final member in type.memberTypes) {
      if (report.isFull) {
        return;
      }
      _member(type, member, included, places[member.name]!);
    }
  }

  void _member(
    UnionType type,
    NamedTypeReference member,
    Set<String> included,
    List<SourceSpan?> places,
  ) {
    if (!TypeReferenceRules(
      report,
      schema,
    ).isKnown(member.name, member.span)) {
      return;
    }
    if (!included.add(member.name)) {
      report.error(
        .repeatedUnionMember,
        'Union type ${type.name} can only include type ${member.name} once.',
        places,
      );
    } else if (schema.typeNamed(member.name) is! ObjectType) {
      report.error(
        .nonObjectUnionMember,
        'Union type ${type.name} can only include Object types, it cannot '
        'include ${member.name}.',
        places,
      );
    }
  }
}
