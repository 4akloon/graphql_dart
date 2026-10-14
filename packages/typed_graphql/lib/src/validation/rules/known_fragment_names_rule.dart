import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.2.1 "Fragment spread target defined": a fragment spread names
/// a fragment the document defines (`GQL215`).
///
/// {@category validation}
final class const KnownFragmentNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _KnownFragmentNames(context);
}

final class _KnownFragmentNames(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node case FragmentSpread(:final name)
        when context.fragmentNamed(name.value) == null) {
      context.report(
        .knownFragmentNames,
        'Unknown fragment "${name.value}".',
        [name],
      );
    }
    return .next;
  }
}
