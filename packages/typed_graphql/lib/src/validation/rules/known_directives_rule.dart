import '../../language/ast/directive.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.7.1 "Directives Are Defined": every directive applied is defined
/// by the schema (`GQL222`).
///
/// graphql-js reports unknown and misplaced directives from one rule; here
/// this rule reports only the unknown ones and
/// `DirectivesInValidLocationsRule` the misplaced ones.
///
/// {@category validation}
final class const KnownDirectivesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _KnownDirectives(context);
}

final class _KnownDirectives(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case Directive(:final name)
        when context.schema.directiveNamed(name.value) == null) {
      context.report(.knownDirectives, 'Unknown directive "@${name.value}".', [
        node,
      ]);
    }
    return .next;
  }
}
