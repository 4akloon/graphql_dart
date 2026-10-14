import '../../language/ast/executable_definition.dart';
import '../../language/ast/name.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.2.2.1 "Operation Name Uniqueness": no two operations share a
/// name (`GQL202`).
///
/// {@category validation}
final class const UniqueOperationNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueOperationNames(context);
}

final class _UniqueOperationNames(final ValidationContext context)
    extends AstVisitor {
  final Map<String, Name> _known = {};

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition(:final name?):
        if (_known[name.value] case final known?) {
          context.report(
            .uniqueOperationNames,
            'There can be only one operation named "${name.value}".',
            [known, name],
          );
        } else {
          _known[name.value] = name;
        }
        return .skip;
      case ExecutableDefinition():
        return .skip;
      default:
        return .next;
    }
  }
}
