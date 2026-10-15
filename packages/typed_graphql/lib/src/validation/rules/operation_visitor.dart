import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';

/// A rule visitor that checks each operation once the walk left the
/// document, when the fragment closures of the operations are known.
///
/// Operations are checked in document order, which is graphql-js's order
/// within a rule.
abstract base class OperationVisitor extends AstVisitor {
  final List<OperationDefinition> _operations = [];

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case final OperationDefinition operation:
        _operations.add(operation);
        return .skip;
      case FragmentDefinition():
        return .skip;
      default:
        return .next;
    }
  }

  @override
  void leave(Node node) {
    if (node is Document) {
      _operations.forEach(checkOperation);
    }
  }

  /// Reports the errors of [operation].
  void checkOperation(OperationDefinition operation);
}
