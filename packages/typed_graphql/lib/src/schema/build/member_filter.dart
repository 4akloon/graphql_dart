import '../../diagnostics/diagnostic_code.dart';
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
/// It filters syntax nodes and rebuilds them with [Node.withChildren], so
/// the readers see only kept members; a type extension is filtered against
/// the members its type already has ([members]). The messages are graphql-js's
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
      node.withChildren(members(node.name.value, node.children, const {}))
          as TypeDefinition;

  /// [node] without repeated arguments.
  DirectiveDefinition directive(DirectiveDefinition node) =>
      node.withChildren(_arguments('@${node.name.value}', node.children))
          as DirectiveDefinition;

  /// [children] of a definition or an extension of the type [typeName]
  /// without the members named in [earlier] or before in [children]; the
  /// kept fields lose their repeated arguments.
  ///
  /// [earlier] maps the names of the members the type already has to their
  /// spans; a name in [inSchema] came from the schema being extended,
  /// which graphql-js words differently.
  List<Node> members(
    String typeName,
    List<Node> children,
    Map<String, SourceSpan?> earlier, {
    Set<String> inSchema = const {},
  }) {
    final seen = {...earlier};
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
          final isInSchema = inSchema.contains(name.value);
          final (code, noun) = switch (member) {
            EnumValueDefinition() => (
              DiagnosticCode.duplicateEnumValueName,
              'Enum value',
            ),
            _ => (DiagnosticCode.duplicateFieldName, 'Field'),
          };
          report.error(
            code,
            _message(noun, '$typeName.${name.value}', isInSchema: isInSchema),
            name,
            related: isInSchema ? null : seen[name.value],
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

  /// Not [members]: arguments have no earlier members and no "already in
  /// the schema" wording, and their repeat is `GQL105`.
  List<Node> _arguments(String owner, List<Node> children) {
    final seen = <String, SourceSpan?>{};
    final kept = <Node>[];
    for (final child in children) {
      if (child case InputValueDefinition(:final name)) {
        if (seen.containsKey(name.value)) {
          report.error(
            .duplicateArgumentName,
            'Argument "$owner(${name.value}:)" can only be defined once.',
            name,
            related: seen[name.value],
          );
          continue;
        }
        seen[name.value] = report.spans.of(child);
      }
      kept.add(child);
    }
    return kept;
  }

  String _message(
    String noun,
    String coordinate, {
    required bool isInSchema,
  }) => isInSchema
      ? '$noun "$coordinate" already exists in the schema. It cannot also '
            'be defined in this type extension.'
      : '$noun "$coordinate" can only be defined once.';

  Name? _memberName(Node node) => switch (node) {
    FieldDefinition(:final name) => name,
    InputValueDefinition(:final name) => name,
    EnumValueDefinition(:final name) => name,
    _ => null,
  };
}
