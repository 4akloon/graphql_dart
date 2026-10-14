import '../../diagnostics/source_span.dart';
import '../../language/ast/type_ref.dart';
import '../../language/ast/value.dart';
import 'applied_directive.dart';
import 'applied_directives.dart';

/// An argument of a field or a directive, or a field of an input object
/// type: `"desc" name: Type = default @d` (spec §3.6.1, §3.10).
///
/// {@category schema}
final class InputValue(
  /// The name.
  final String name,

  /// The input type, by name: resolve it with `Schema.typeNamed`.
  final TypeRef type, {

  /// The description, if any.
  final String? description,

  /// The default value, a constant; null when there is none.
  final Value? defaultValue,
  List<AppliedDirective> appliedDirectives = const [],

  /// Where it was defined; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates an input value.
  this;

  /// The directives applied to it, in the order written.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  /// The reason it is deprecated; null when it is not.
  String? get deprecationReason =>
      AppliedDirectives(appliedDirectives).deprecationReason;
}
