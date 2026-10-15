import '../../language/ast/document.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../overlap/field_merging.dart';
import '../overlap/field_origin.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.3.2 "Field Selection Merging": fields with one response name
/// that may be selected together select the same field with the same
/// arguments, and all fields with that name have the same response shape
/// (`GQL206`).
///
/// graphql-js compares fields pairwise, quadratic in the size of a
/// selection (graphql-js#2185); this rule merges them level by level in
/// linear time (R3.3) and reports each conflicting pair of fields once,
/// with graphql-js's messages, for the nearest pair of distinct
/// ancestors. With three or more conflicting fields of one name, a field
/// is reported against the first field of each other kind, not against
/// every one, so there may be fewer reports than in graphql-js.
///
/// {@category validation}
final class const OverlappingFieldsCanBeMergedRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _OverlappingFields(context);
}

final class _OverlappingFields(final ValidationContext context)
    extends AstVisitor {
  final Map<Field, FieldOrigin> _origins = Map.identity();

  @override
  VisitAction enter(Node node) {
    if (node is Field) {
      _origins[node] = FieldOrigin(context.typeInfo.parentType);
    }
    return .next;
  }

  @override
  void leave(Node node) {
    if (node is Document && !context.isAborted) {
      FieldMerging(context, _origins).check();
    }
  }
}
