import '../../diagnostics/source_span.dart';
import '../../language/ast/node.dart';

/// The span of a syntax node held by a schema element, such as a field's
/// type or an argument's default value, so an error points where
/// graphql-js points.
///
/// The model keeps a span for the element only; a node it holds was read
/// from the same source, so the element's source and the node's offsets
/// give the node's span.
final class const NodeSpan() {
  /// Creates the function; it keeps no state.
  this;

  /// The span of [node] in the source of [element]; null when the
  /// element has no span (it was built in code).
  SourceSpan? within(SourceSpan? element, Node node) => switch (element) {
    final element? => SourceSpan(element.source, node.start, node.end),
    null => null,
  };
}
