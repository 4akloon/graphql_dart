import '../ast/node.dart';

/// Rebuilds a syntax tree bottom-up (R1.9): [rewrite] sees each node after
/// its children were rewritten and returns what takes its place.
///
/// Returning the node keeps it, another node replaces it, and null removes
/// it from its parent's children. The parent is rebuilt with
/// [Node.withChildren], so the parent decides what it accepts: removing a
/// child it requires, such as the value of an argument, is a [StateError].
/// A branch where nothing changed keeps its instance, so `identical`
/// tells whether a transform changed anything.
///
/// Like `AstWalker`, it keeps its own stack instead of recursing.
///
/// {@category language}
abstract class AstTransformer {
  /// Creates a transformer.
  const AstTransformer();

  /// What takes the place of [node], whose children are already
  /// rewritten: [node] itself to keep it, another node, or null to remove
  /// it. Keeps every node by default.
  Node? rewrite(Node node) => node;

  /// [root] rewritten bottom-up; null when [rewrite] removed [root] itself.
  Node? transform(Node root) {
    final frames = [_Frame(root)];
    Node? rewritten;
    while (frames.isNotEmpty) {
      final frame = frames.last;
      if (frame.hasNext) {
        frames.add(_Frame(frame.takeNext()));
        continue;
      }
      frames.removeLast();
      rewritten = rewrite(frame.rebuild());
      if (rewritten != null && frames.isNotEmpty) {
        frames.last.add(rewritten);
      }
    }
    return rewritten;
  }
}

/// A node being rebuilt: the children still to rewrite and the rewritten
/// ones so far.
final class _Frame {
  _Frame(this.node) : _children = node.children;

  final Node node;
  final List<Node> _children;
  final List<Node> _rewritten = [];
  int _next = 0;

  bool get hasNext => _next < _children.length;

  Node takeNext() => _children[_next++];

  void add(Node child) => _rewritten.add(child);

  /// [node] with the rewritten children; [node] itself when each one is
  /// identical to the child it replaces.
  Node rebuild() => node.withChildren(_rewritten);
}
