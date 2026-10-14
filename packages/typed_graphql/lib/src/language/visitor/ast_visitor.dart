import '../ast/node.dart';
import 'visit_action.dart';

/// Receives the nodes of a syntax tree as an `AstWalker` walks it (R1.9):
/// [enter] before a node's children, [leave] after them.
///
/// Both do nothing by default, so a visitor overrides only what it needs
/// and tells node kinds apart with a `switch` over the sealed families.
abstract class AstVisitor {
  /// Creates a visitor.
  const AstVisitor();

  /// Called before the children of [node]. [VisitAction.next] goes into
  /// them, [VisitAction.skip] passes over them without calling [leave] for
  /// [node], and [VisitAction.stop] ends the walk.
  VisitAction enter(Node node) => VisitAction.next;

  /// Called after the children of [node], when [enter] returned
  /// [VisitAction.next] for it.
  void leave(Node node) {}
}
