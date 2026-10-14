import '../../diagnostics/source.dart';
import '../../diagnostics/source_span.dart';
import '../../language/ast/node.dart';

/// Turns the offsets of syntax nodes into spans of the [source] they were
/// parsed from.
///
/// A document carries no source, so the builder is given one; without it
/// (a document built in code) every span is null.
final class const NodeSpans(
  /// The text the nodes were parsed from; null when unknown.
  final Source? source,
) {
  /// Creates the spans of nodes parsed from [source].
  this;

  /// The span of [node]; null without a [source].
  SourceSpan? of(Node node) => switch (source) {
    final source? => SourceSpan(source, node.start, node.end),
    null => null,
  };
}
