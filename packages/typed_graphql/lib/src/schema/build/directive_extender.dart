import '../../language/ast/type_system_extension.dart';
import '../model/schema_directive.dart';
import '../schema.dart';
import 'build_report.dart';
import 'element_reader.dart';

/// Applies directive extensions, `extend directive @name @d` (working
/// draft): the directives they apply go after the definition's own.
///
/// An extension of a built-in or of a missing directive is reported and
/// ignored.
final class DirectiveExtender(
  /// Receives the errors and gives the spans.
  final BuildReport report,

  /// The schema being extended, which tells the built-ins it has.
  final Schema base,
) {
  /// Creates an extender.
  this;

  /// [directives] with [extensions] applied, in the order of
  /// [directives]; an extension applies to the first directive of its
  /// name.
  List<SchemaDirective> applyAll(
    List<SchemaDirective> directives,
    List<DirectiveExtension> extensions,
  ) {
    final extended = [...directives];
    final indexes = <String, int>{};
    for (final (index, directive) in directives.indexed) {
      indexes.putIfAbsent(directive.name, () => index);
    }
    for (final node in extensions) {
      final name = node.name.value;
      if (indexes[name] case final index?) {
        extended[index] = _extend(extended[index], node);
      } else if (base.directiveNamed(name) != null) {
        report.error(
          .builtInRedefinition,
          'The built-in directive "@$name" cannot be extended.',
          node.name,
        );
      } else {
        report.error(
          .unknownExtensionTarget,
          'Cannot extend directive "@$name" because it is not defined.',
          node.name,
        );
      }
    }
    return extended;
  }

  SchemaDirective _extend(SchemaDirective directive, DirectiveExtension node) =>
      SchemaDirective(
        directive.name,
        description: directive.description,
        arguments: directive.arguments,
        isRepeatable: directive.isRepeatable,
        locations: directive.locations,
        appliedDirectives: [
          ...directive.appliedDirectives,
          ...ElementReader(report.spans).appliedAll(node.directives),
        ],
        span: directive.span,
      );
}
