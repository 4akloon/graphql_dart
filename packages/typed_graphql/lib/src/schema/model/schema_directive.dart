import '../../diagnostics/source_span.dart';
import '../../language/ast/directive_location.dart';
import 'applied_directive.dart';
import 'applied_directives.dart';
import 'input_value.dart';

/// A directive definition, `"desc" directive @name(args) repeatable on
/// LOCATIONS` (spec §3.13).
///
/// The language node with the spec's name is `DirectiveDefinition`; this
/// is the schema's element. Directives applied to a directive definition
/// are working-draft syntax (`ParserOptions.allowDirectiveExtensions`).
///
/// {@category schema}
final class SchemaDirective(
  /// The directive name, without the `@`.
  final String name, {

  /// The description, if any.
  final String? description,
  List<InputValue> arguments = const [],

  /// Whether it may be applied more than once to one place.
  final bool isRepeatable = false,
  List<DirectiveLocation> locations = const [],
  List<AppliedDirective> appliedDirectives = const [],

  /// Where it was defined; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates a directive definition.
  this;

  /// The arguments, in declaration order.
  final List<InputValue> arguments = List.unmodifiable(arguments);

  /// The locations it may be applied to, in the order written.
  final List<DirectiveLocation> locations = List.unmodifiable(locations);

  /// The directives applied to the definition itself, in the order written.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  /// The reason it is deprecated; null when it is not.
  String? get deprecationReason =>
      AppliedDirectives(appliedDirectives).deprecationReason;

  /// The argument named [name]; null when there is none.
  InputValue? argumentNamed(String name) {
    for (final argument in arguments) {
      if (argument.name == name) {
        return argument;
      }
    }
    return null;
  }
}
