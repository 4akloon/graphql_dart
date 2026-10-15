import '../../language/ast/executable_definition.dart';
import '../../language/ast/name.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.1.1 "Fragment Name Uniqueness": a document defines each
/// fragment name once (`GQL211`).
///
/// The error points at the first name and relates to the repeat.
///
/// {@category validation}
final class const UniqueFragmentNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueFragmentNames(context);
}

final class _UniqueFragmentNames(final ValidationContext context)
    extends AstVisitor {
  final Map<String, Name> _knownNames = {};

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case OperationDefinition():
        return .skip;
      case FragmentDefinition(:final name):
        if (_knownNames[name.value] case final known?) {
          context.report(
            .uniqueFragmentNames,
            'There can be only one fragment named "${name.value}".',
            [known, name],
          );
        } else {
          _knownNames[name.value] = name;
        }
        return .skip;
      default:
        return .next;
    }
  }
}
