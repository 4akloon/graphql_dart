import '../../diagnostics/source_span.dart';
import 'applied_directive.dart';
import 'applied_directives.dart';

/// A value of an enum type, `"desc" NAME @d` (spec §3.9).
///
/// The language nodes with the spec's names are `EnumValueDefinition` and,
/// for a literal, `EnumValue`; this is the schema's element.
///
/// {@category schema}
final class SchemaEnumValue(
  /// The value's name.
  final String name, {

  /// The description, if any.
  final String? description,
  List<AppliedDirective> appliedDirectives = const [],

  /// Where it was defined; null when it was not read from SDL.
  final SourceSpan? span,
}) {
  /// Creates an enum value.
  this;

  /// The directives applied to it, in the order written.
  final List<AppliedDirective> appliedDirectives = List.unmodifiable(
    appliedDirectives,
  );

  /// The reason it is deprecated; null when it is not.
  String? get deprecationReason =>
      AppliedDirectives(appliedDirectives).deprecationReason;
}
