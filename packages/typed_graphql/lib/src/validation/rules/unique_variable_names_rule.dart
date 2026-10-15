import '../../language/ast/executable_definition.dart';
import '../../language/ast/name.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.8.1 "Variable Uniqueness": an operation declares each variable
/// name once (`GQL225`).
///
/// The error points at the first name and relates to the others.
///
/// {@category validation}
final class const UniqueVariableNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueVariableNames(context);
}

final class _UniqueVariableNames(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition(:final variableDefinitions):
        _check([
          for (final definition in variableDefinitions)
            definition.variable.name,
        ]);
        return .skip;
      case FragmentDefinition():
        return .skip;
      default:
        return .next;
    }
  }

  void _check(List<Name> names) {
    final byName = <String, List<Name>>{};
    for (final name in names) {
      (byName[name.value] ??= []).add(name);
    }
    for (final MapEntry(:key, :value) in byName.entries) {
      if (value.length > 1) {
        context.report(
          .uniqueVariableNames,
          'There can be only one variable named "\$$key".',
          value,
        );
      }
    }
  }
}
