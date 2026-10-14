import '../../diagnostics/source_span.dart';
import '../../language/ast/enum_value_definition.dart';
import '../../language/ast/field_definition.dart';
import '../../language/ast/input_value_definition.dart';
import '../../language/ast/name.dart';
import '../../language/ast/node.dart';
import '../../language/ast/type_system_definition.dart';
import 'build_report.dart';

/// Drops the repeated members of type and directive definitions, keeping
/// the first of each name and reporting the others.
///
/// It filters syntax nodes and rebuilds them with `withChildren`, so the
/// readers see only kept members. The messages are graphql-js's
/// (`UniqueFieldDefinitionNamesRule`, `UniqueEnumValueNamesRule`,
/// `UniqueArgumentDefinitionNamesRule`).
final class MemberFilter(
  /// Receives the errors.
  final BuildReport report,
) {
  /// Creates a filter.
  this;

  /// [node] without repeated fields, input fields, enum values and field
  /// arguments.
  TypeDefinition definition(TypeDefinition node) =>
      node.withChildren(_members(node.name.value, node.children))
          as TypeDefinition;

  /// [node] without repeated arguments.
  DirectiveDefinition directive(DirectiveDefinition node) =>
      node.withChildren(_arguments('@${node.name.value}', node.children))
          as DirectiveDefinition;

  List<Node> _members(String typeName, List<Node> children) {
    final seen = <String, SourceSpan?>{};
    final kept = <Node>[];
    for (final child in children) {
      final member = switch (child) {
        FieldDefinition(:final name) => child.withChildren(
          _arguments('$typeName.${name.value}', child.children),
        ),
        _ => child,
      };
      switch (_memberName(member)) {
        case final name? when seen.containsKey(name.value):
          final isEnumValue = member is EnumValueDefinition;
          report.error(
            isEnumValue ? .duplicateEnumValueName : .duplicateFieldName,
            '${isEnumValue ? 'Enum value' : 'Field'} '
            '"$typeName.${name.value}" can only be defined once.',
            name,
            related: seen[name.value],
          );
        case final name?:
          seen[name.value] = report.spans.of(member);
          kept.add(member);
        case null:
          kept.add(member);
      }
    }
    return kept;
  }

  List<Node> _arguments(String owner, List<Node> children) {
    final seen = <String, SourceSpan?>{};
    final kept = <Node>[];
    for (final child in children) {
      if (child case InputValueDefinition(:final name)
          when seen.containsKey(name.value)) {
        report.error(
          .duplicateArgumentName,
          'Argument "$owner(${name.value}:)" can only be defined once.',
          name,
          related: seen[name.value],
        );
        continue;
      }
      if (child case InputValueDefinition(:final name)) {
        seen[name.value] = report.spans.of(child);
      }
      kept.add(child);
    }
    return kept;
  }

  Name? _memberName(Node node) => switch (node) {
    FieldDefinition(:final name) => name,
    InputValueDefinition(:final name) => name,
    EnumValueDefinition(:final name) => name,
    _ => null,
  };
}
