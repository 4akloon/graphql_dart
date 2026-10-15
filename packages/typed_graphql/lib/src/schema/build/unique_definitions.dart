import '../../language/ast/type_system_definition.dart';
import '../schema.dart';
import 'build_report.dart';
import 'built_ins.dart';

/// Keeps the first type or directive definition of each name and drops
/// the repeats and the built-ins redefined, reporting each.
///
/// The messages are graphql-js's (`UniqueTypeNamesRule`,
/// `UniqueDirectiveNamesRule`); a repeat points at its name and relates
/// to the definition it repeats.
final class UniqueDefinitions(
  /// Receives the errors.
  final BuildReport report,

  /// The schema the definitions are added to; its types and directives
  /// count as defined first.
  final Schema base,
) {
  /// Creates the check.
  this;

  /// [nodes] without repeated or built-in names.
  List<TypeDefinition> types(List<TypeDefinition> nodes) {
    final kept = <String, TypeDefinition>{};
    for (final node in nodes) {
      final name = node.name.value;
      if (const BuiltIns().typeNamed(name) != null) {
        report.error(
          .builtInRedefinition,
          'The built-in type "$name" cannot be redefined.',
          node.name,
        );
      } else if (base.typeNamed(name) != null) {
        report.error(
          .duplicateTypeName,
          'Type "$name" already exists in the schema. It cannot also be '
          'defined in this type definition.',
          node.name,
        );
      } else if (kept[name] case final first?) {
        report.error(
          .duplicateTypeName,
          'There can be only one type named "$name".',
          node.name,
          related: report.spans.of(first),
        );
      } else {
        kept[name] = node;
      }
    }
    return [...kept.values];
  }

  /// [nodes] without repeated or built-in names.
  List<DirectiveDefinition> directives(List<DirectiveDefinition> nodes) {
    final kept = <String, DirectiveDefinition>{};
    for (final node in nodes) {
      final name = node.name.value;
      if (const BuiltIns().isBuiltInDirective(
        name,
        includesDeferAndStream: base.includesDeferAndStream,
        includesCostDirectives: base.includesCostDirectives,
      )) {
        report.error(
          .builtInRedefinition,
          'The built-in directive "@$name" cannot be redefined.',
          node.name,
        );
      } else if (base.directiveNamed(name) != null) {
        report.error(
          .duplicateDirectiveName,
          'Directive "@$name" already exists in the schema. It cannot be '
          'redefined.',
          node.name,
        );
      } else if (kept[name] case final first?) {
        report.error(
          .duplicateDirectiveName,
          'There can be only one directive named "@$name".',
          node.name,
          related: report.spans.of(first),
        );
      } else {
        kept[name] = node;
      }
    }
    return [...kept.values];
  }
}
