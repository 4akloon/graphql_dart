import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'comment.dart';
import 'ignored_chars.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';
import 'source_location.dart';

abstract interface class Node<T extends Node<dynamic>> {
  List<Node> get children;

  NodeChildrenContainer get namedChildren;

  T withNewChildren(NodeChildrenContainer newChildren);

  SourceLocation? get sourceLocation;

  List<Comment> get comments;

  IgnoredChars get ignoredChars;

  Map<String, String> get additionalData;

  bool isEqualTo(Node node);

  T deepCopy();

  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor);
}
