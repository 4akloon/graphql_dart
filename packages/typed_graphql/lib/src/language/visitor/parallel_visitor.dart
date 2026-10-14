import '../ast/node.dart';
import 'ast_visitor.dart';
import 'visit_action.dart';

/// Runs several visitors in one walk (R1.9), as graphql-js's
/// `visitInParallel` does: each visitor is called exactly as if it walked
/// the tree alone.
///
/// A visitor that skips a node is not called again until the walk leaves
/// that node; a visitor that stops is not called again. The walk itself
/// passes over a node that every running visitor skips, and ends when
/// every visitor has stopped (at once for an empty list). It keeps that
/// state as it goes, so each walk needs a new one.
final class ParallelVisitor extends AstVisitor {
  /// Creates a visitor that runs [visitors], in order, at every node.
  ParallelVisitor(List<AstVisitor> visitors)
    : visitors = List.unmodifiable(visitors),
      _skippedAt = List.filled(visitors.length, null),
      _isStopped = List.filled(visitors.length, false);

  /// The visitors, in the order they are called at each node.
  final List<AstVisitor> visitors;

  /// For each visitor, the node whose children it skips; null while it
  /// runs.
  final List<Node?> _skippedAt;

  /// For each visitor, whether it stopped.
  final List<bool> _isStopped;

  @override
  VisitAction enter(Node node) {
    var isAnyRunning = false;
    for (var i = 0; i < visitors.length; i++) {
      if (_isStopped[i] || _skippedAt[i] != null) {
        continue;
      }
      switch (visitors[i].enter(node)) {
        case VisitAction.next:
          isAnyRunning = true;
        case VisitAction.skip:
          _skippedAt[i] = node;
        case VisitAction.stop:
          _isStopped[i] = true;
      }
    }
    if (_isStopped.every((isStopped) => isStopped)) {
      return VisitAction.stop;
    }
    return isAnyRunning ? VisitAction.next : _skipAll(node);
  }

  @override
  void leave(Node node) {
    for (var i = 0; i < visitors.length; i++) {
      if (_isStopped[i]) {
        continue;
      }
      if (_skippedAt[i] == null) {
        visitors[i].leave(node);
      } else if (identical(_skippedAt[i], node)) {
        _skippedAt[i] = null;
      }
    }
  }

  /// The walk will not leave [node], so the visitors that skipped it run
  /// again after it.
  VisitAction _skipAll(Node node) {
    for (var i = 0; i < visitors.length; i++) {
      if (identical(_skippedAt[i], node)) {
        _skippedAt[i] = null;
      }
    }
    return VisitAction.skip;
  }
}
