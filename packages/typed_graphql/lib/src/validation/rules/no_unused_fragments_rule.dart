import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.1.4 "Fragments Must Be Used": every fragment is spread by an
/// operation, directly or through other fragments (`GQL214`).
///
/// Reported when the walk leaves the document, in definition order.
///
/// {@category validation}
final class const NoUnusedFragmentsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _NoUnusedFragments(context);
}

final class _NoUnusedFragments(final ValidationContext context)
    extends AstVisitor {
  final List<OperationDefinition> _operations = [];
  final List<FragmentDefinition> _fragments = [];

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case final OperationDefinition operation:
        _operations.add(operation);
        return .skip;
      case final FragmentDefinition fragment:
        _fragments.add(fragment);
        return .skip;
      default:
        return .next;
    }
  }

  @override
  void leave(Node node) {
    if (node is! Document) {
      return;
    }
    final usedNames = {
      for (final operation in _operations)
        for (final fragment in context.recursivelyReferencedFragments(
          operation,
        ))
          fragment.name.value,
    };
    for (final fragment in _fragments) {
      if (!usedNames.contains(fragment.name.value)) {
        context.report(
          .noUnusedFragments,
          'Fragment "${fragment.name.value}" is never used.',
          [fragment],
        );
      }
    }
  }
}
