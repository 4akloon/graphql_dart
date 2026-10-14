import '../../language/ast/directive_location.dart';
import '../../protocol/path_segment.dart';
import '../model/schema_directive.dart';
import 'introspection_annotations.dart';
import 'introspection_object.dart';
import 'member_reader.dart';

/// Reads the directives of an introspection result (graphql-js's
/// `buildDirective`).
final class DirectiveDefinitionReader(
  /// Reads the arguments of the directives.
  final MemberReader members,
) {
  /// Creates a reader.
  this;

  /// The directive [directive] describes; null, after a report, without a
  /// name, `args` or `locations`.
  SchemaDirective? read(IntrospectionObject directive) {
    final name = directive.string('name');
    final arguments = directive.list('args', what: 'directive args');
    final locations = _locations(directive);
    if (name == null || arguments == null || locations == null) {
      return null;
    }
    return SchemaDirective(
      name,
      description: directive.optionalString('description'),
      arguments: members.inputValues(arguments),
      isRepeatable: directive.flag('isRepeatable'),
      locations: locations,
      appliedDirectives: const IntrospectionAnnotations().deprecated(
        directive,
      ),
    );
  }

  /// The `locations` of [directive]; an unknown spelling is reported and
  /// left out.
  List<DirectiveLocation>? _locations(IntrospectionObject directive) {
    final spellings = directive.strings(
      'locations',
      what: 'directive locations',
    );
    if (spellings == null) {
      return null;
    }
    final locations = <DirectiveLocation>[];
    for (final (index, spelling) in spellings) {
      if (DirectiveLocation.named(spelling) case final location?) {
        locations.add(location);
      } else {
        directive.report(
          .malformedIntrospectionMember,
          'Unknown directive location "$spelling".',
          inside: [const PathKey('locations'), PathIndex(index)],
        );
      }
    }
    return locations;
  }
}
