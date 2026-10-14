import '../../diagnostics/source_span.dart';
import '../../language/ast/type_ref.dart';
import 'applied_directive.dart';
import 'applied_directives.dart';
import 'input_value.dart';

/// A field of an object or interface type, `"desc" name(args): Type @d`
/// (spec §3.6).
///
/// The language node with the spec's name is `FieldDefinition`; this is
/// the schema's element.
final class SchemaField(
  /// The field name.
  final String name,

  /// The output type, by name: resolve it with `Schema.typeNamed`.
  final TypeRef type, {

  /// The description, if any.
  final String? description,
  List<InputValue> arguments = const [],
  List<AppliedDirective> appliedDirectives = const [],

  /// Where it was defined; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates a field.
  this;

  /// The arguments, in declaration order.
  final List<InputValue> arguments = List.unmodifiable(arguments);

  /// The directives applied to it, in the order written.
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
