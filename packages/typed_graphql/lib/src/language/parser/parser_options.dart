import 'package:meta/meta.dart';

/// What a [Parser] accepts and how much: limits against abuse (R1.6) and
/// working-draft grammar (R0.1, R1.4).
@immutable
final class const ParserOptions({
  /// The most tokens a document may have; null for no limit.
  final int? maxTokens = 15000,

  /// The deepest nesting of selection sets, lists, objects and list types;
  /// null for no limit, which lets a hostile document exhaust the stack.
  ///
  /// The parser recurses on nested values, so a limit near 1000 (or null)
  /// can overflow the stack on deeply nested object values; the default
  /// of 128 is safe.
  final int? maxDepth = 128,

  /// Whether the working draft's directive extensions are accepted:
  /// `extend directive @name @directive`, directives on a directive
  /// definition and the `DIRECTIVE_DEFINITION` location.
  final bool allowDirectiveExtensions = false,

  /// Whether the working draft's empty selection set, `{ }`, is accepted.
  final bool allowEmptySelectionSets = false,
}) {
  /// Creates options; the defaults are the September2025 grammar.
  this;
}
