import 'package:meta/meta.dart';

import 'child_reader.dart';

/// A node of the syntax tree of a GraphQL document; immutable.
///
/// [start] and [end] are UTF-16 offsets into the source the node was parsed
/// from (R1.7); a node built in code has 0 for both. Nodes do not override
/// `==`: [isEquivalentTo] compares structure and ignores positions.
///
/// {@category language}
abstract class const Node({
  /// The offset of the first code unit of the node.
  final int start = 0,

  /// The offset after the last code unit of the node.
  final int end = 0,
}) {
  /// Creates a node spanning [start] to [end].
  this;

  /// The child nodes in grammar order, the order of graphql-js's
  /// `QueryDocumentKeys`; an absent optional child is left out. A read-only
  /// view: never modify it (some nodes return a fresh list, others a
  /// covariant list on which `add` throws).
  List<Node> get children;

  /// The scalar fields [isEquivalentTo] compares, such as a name's value or
  /// an operation's type; empty for a node that has none.
  @protected
  List<Object?> get scalars => const [];

  /// A copy of this node with [children] in place of [Node.children], in
  /// the same order and shape, keeping [start] and [end]; this node itself
  /// when every child is identical.
  ///
  /// Throws a [StateError] when [children] does not fit the node: a missing
  /// required child, a child of the wrong kind or one too many.
  Node withChildren(List<Node> children) =>
      ChildReader(children).rebuild(this, rebuildFrom);

  /// A node of this kind with this node's scalar fields and positions and
  /// the children [read] returns, in the order of [children]; a leaf
  /// returns itself. Only [withChildren] calls it.
  @protected
  Node rebuildFrom(ChildReader read);

  /// Whether [other] has the same kind, the same scalar fields and
  /// equivalent children, in order; positions are ignored.
  ///
  /// It recurses over the tree, so it is bounded by the parser's
  /// `maxDepth`.
  bool isEquivalentTo(Node other) {
    if (other.runtimeType != runtimeType ||
        !_sameScalars(scalars, other.scalars)) {
      return false;
    }
    final mine = children;
    final theirs = other.children;
    if (mine.length != theirs.length) {
      return false;
    }
    for (var i = 0; i < mine.length; i++) {
      if (!mine[i].isEquivalentTo(theirs[i])) {
        return false;
      }
    }
    return true;
  }

  static bool _sameScalars(List<Object?> left, List<Object?> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }
}
