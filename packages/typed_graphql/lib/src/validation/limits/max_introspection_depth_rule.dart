import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'selection_measure.dart';

/// Limits the nesting of the lists of the introspection types (R3.5,
/// `GQL236`): below a `__schema` or `__type` field, no path may pass
/// through three fields named `fields`, `interfaces`, `possibleTypes` or
/// `inputFields`, fragments expanded.
///
/// A port of graphql-js's `MaxIntrospectionDepthRule`. Where it walks the
/// fragments again for each path, this rule measures each fragment once, so
/// its time is linear in the document. The error is reported at the
/// `__schema` or `__type` field, whose subtree the rule then skips. The rule
/// is in [DocumentValidator.recommendedRules], not in the specified rules.
///
/// {@category validation}
final class const MaxIntrospectionDepthRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) => _MaxIntrospectionDepth(
    context,
    SelectionMeasure(context, .introspectionLists, _maxListsDepth - 1),
  );
}

// graphql-js's MAX_LISTS_DEPTH: a path with this many lists is too deep.
const int _maxListsDepth = 3;

final class _MaxIntrospectionDepth(
  final ValidationContext context,
  final SelectionMeasure measure,
) extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is! Field) {
      return .next;
    }
    final name = node.name.value;
    final selectionSet = node.selectionSet;
    if ((name != '__schema' && name != '__type') || selectionSet == null) {
      return .next;
    }
    final value = measure.measureSelections(selectionSet.selections);
    if (value != null && value > measure.limit) {
      context.report(
        .maxIntrospectionDepthExceeded,
        'Maximum introspection depth exceeded',
        [node],
      );
      return .skip;
    }
    return .next;
  }
}
