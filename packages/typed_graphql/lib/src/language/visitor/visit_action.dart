/// What a walk does after `AstVisitor.enter` returns, as graphql-js's
/// `visit` does with `undefined`, `false` and `BREAK`.
enum VisitAction {
  /// Visit the node's children, then leave the node.
  next,

  /// Pass over the node's children; the node is not left either.
  skip,

  /// End the walk: no other node is entered or left.
  stop,
}
