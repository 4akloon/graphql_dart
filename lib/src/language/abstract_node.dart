import 'comment.dart';
import 'ignored_chars.dart';
import 'node.dart';
import 'source_location.dart';

abstract class AbstractNode<T extends Node<dynamic>> implements Node<T> {
  @override
  final SourceLocation? sourceLocation;
  @override
  final List<Comment> comments;
  @override
  final IgnoredChars ignoredChars;
  @override
  final Map<String, String> additionalData;

  AbstractNode({
    this.sourceLocation,
    required this.ignoredChars,
    required List<Comment> comments,
    Map<String, String> additionalData = const {},
  })  : comments = List.unmodifiable(comments),
        additionalData = Map.unmodifiable(additionalData);

  V? deepCopyFromNode<V extends Node>(V? node) {
    if (node == null) {
      return null;
    }
    return node.deepCopy() as V;
  }

  List<V>? deepCopyFromNodes<V extends Node>(List<V>? nodes) {
    if (nodes == null) {
      return null;
    }
    return nodes.map((node) => node.deepCopy() as V).toList();
  }
}
