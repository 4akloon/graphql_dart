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
  ///
  /// The extensions of one directive are grouped first (document order
  /// kept) and the directive is rebuilt once, so extending it N times is
  /// linear.
  List<SchemaDirective> applyAll(
    List<SchemaDirective> directives,
    List<DirectiveExtension> extensions,
  ) {
    final indexes = <String, int>{};
    for (final (index, directive) in directives.indexed) {
      indexes.putIfAbsent(directive.name, () => index);
    }
    final grouped = <int, List<DirectiveExtension>>{};
    for (final node in extensions) {
      final name = node.name.value;
      if (indexes[name] case final index?) {
        (grouped[index] ??= []).add(node);
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
    final extended = [...directives];
    for (final MapEntry(key: index, value: nodes) in grouped.entries) {
      extended[index] = _extend(directives[index], nodes);
    }
    return extended;
  }

  /// Every field of [directive] but the applied directives, which gain
  /// those of [nodes]; a field added to [SchemaDirective] must be copied
  /// here too.
  SchemaDirective _extend(
    SchemaDirective directive,
    List<DirectiveExtension> nodes,
  ) => SchemaDirective(
    directive.name,
    description: directive.description,
    arguments: directive.arguments,
    isRepeatable: directive.isRepeatable,
    locations: directive.locations,
    appliedDirectives: [
      ...directive.appliedDirectives,
      for (final node in nodes) ..._elements.appliedAll(node.directives),
    ],
    span: directive.span,
  );

  final ElementReader _elements = ElementReader(report.spans);
}
