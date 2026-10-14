import 'child_reader.dart';
import 'definition.dart';
import 'node.dart';

/// A GraphQL document: a list of definitions (spec §2.2).
///
/// {@category language}
final class Document(
  List<Definition> definitions, {
  super.start,
  super.end,
}) extends Node {
  /// Creates a document.
  this;

  /// The definitions, in source order.
  final List<Definition> definitions = List.unmodifiable(definitions);

  @override
  List<Node> get children => definitions;

  @override
  Document rebuildFrom(ChildReader read) =>
      Document(read.all(), start: start, end: end);
}
