import '../language/ast/executable_definition.dart';
import '../language/ast/node.dart';
import '../language/ast/value.dart';
import '../language/ast/variable_definition.dart';
import '../language/visitor/ast_visitor.dart';
import '../language/visitor/parallel_visitor.dart';
import '../language/visitor/visit_action.dart';
import 'usage_index.dart';
import 'validation_context.dart';

/// The visitor of one validation run (R3.2), graphql-js's
/// `visitWithTypeInfo` around `visitInParallel`: the context's `TypeInfo`
/// enters a node before the rules and leaves it after them, and the usage
/// index records the node first.
///
/// Descriptions are not walked: they do not affect validation (spec
/// §2.2), and graphql-js's `validate` drops the `description` keys.
final class ValidationWalk extends AstVisitor {
  /// Runs [visitors] with [context] and its [usages].
  ValidationWalk(this._context, UsageIndex usages, List<AstVisitor> visitors)
    : _visitors = ParallelVisitor([usages, ...visitors]);

  final ValidationContext _context;
  final ParallelVisitor _visitors;
  // A description is the first child of its definition, so it is the
  // next node entered after the definition.
  StringValue? _description;

  @override
  VisitAction enter(Node node) {
    if (identical(node, _description)) {
      return VisitAction.skip;
    }
    if (_context.isAborted) {
      return VisitAction.stop;
    }
    _description = switch (node) {
      OperationDefinition(:final description) => description,
      FragmentDefinition(:final description) => description,
      VariableDefinition(:final description) => description,
      _ => null,
    };
    _context.typeInfo.enter(node);
    final action = _visitors.enter(node);
    // The walk will not leave a node it does not go into.
    if (action != VisitAction.next) {
      _context.typeInfo.leave(node);
    }
    return action;
  }

  @override
  void leave(Node node) {
    _visitors.leave(node);
    _context.typeInfo.leave(node);
  }
}
