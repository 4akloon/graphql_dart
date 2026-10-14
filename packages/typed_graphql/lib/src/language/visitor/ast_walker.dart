import '../ast/node.dart';
import 'ast_visitor.dart';
import 'visit_action.dart';

/// Walks a syntax tree depth-first through [Node.children] and calls an
/// [AstVisitor] on the way down and on the way up.
///
/// The walk keeps its own stack instead of recursing, so a tree built in
/// code cannot overflow the call stack however deep it is. (A parser
/// without `maxDepth` overflows first, and `Printer.print` and
/// [Node.isEquivalentTo] recurse.)
final class AstWalker {
  /// Creates a walker; it keeps no state between walks.
  const AstWalker();

  /// Walks [root] and everything under it, in the order of
  /// [Node.children], as [visitor] directs.
  void walk(Node root, AstVisitor visitor) {
    final frames = <_Frame>[];
    var action = _enter(root, visitor, frames);
    while (action != VisitAction.stop && frames.isNotEmpty) {
      final frame = frames.last;
      if (frame.hasNext) {
        action = _enter(frame.takeNext(), visitor, frames);
      } else {
        frames.removeLast();
        visitor.leave(frame.node);
      }
    }
  }

  VisitAction _enter(Node node, AstVisitor visitor, List<_Frame> frames) {
    final action = visitor.enter(node);
    if (action == VisitAction.next) {
      frames.add(_Frame(node));
    }
    return action;
  }
}

/// A node being walked and how many of its children were entered.
final class _Frame {
  _Frame(this.node) : _children = node.children;

  final Node node;
  final List<Node> _children;
  int _next = 0;

  bool get hasNext => _next < _children.length;

  Node takeNext() => _children[_next++];
}
