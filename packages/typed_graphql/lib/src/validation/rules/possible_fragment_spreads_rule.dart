import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.5.2.3 "Fragment spread is possible": the type condition of a
/// fragment spread or inline fragment overlaps the parent type (`GQL217`).
///
/// {@category validation}
final class const PossibleFragmentSpreadsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _PossibleFragmentSpreads(context);
}

final class _PossibleFragmentSpreads(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case InlineFragment():
        _checkInline(node);
      case FragmentSpread(:final name):
        _checkSpread(node, name.value);
      default:
    }
    return .next;
  }

  void _checkInline(InlineFragment node) {
    final fragmentType = switch (context.typeInfo.type) {
      final type? => context.schema.namedTypeOf(type),
      null => null,
    };
    final parentType = context.typeInfo.parentType;
    if (_cannotOverlap(fragmentType, parentType)) {
      context.report(
        .possibleFragmentSpreads,
        'Fragment cannot be spread here as objects of type '
        '"${parentType?.name}" can never be of type "${fragmentType?.name}".',
        [node],
      );
    }
  }

  void _checkSpread(FragmentSpread node, String fragmentName) {
    final fragmentType = switch (context.fragmentNamed(fragmentName)) {
      final fragment? => context.schema.namedTypeOf(fragment.typeCondition),
      null => null,
    };
    final parentType = context.typeInfo.parentType;
    if (_cannotOverlap(fragmentType, parentType)) {
      context.report(
        .possibleFragmentSpreads,
        'Fragment "$fragmentName" cannot be spread here as objects of type '
        '"${parentType?.name}" can never be of type "${fragmentType?.name}".',
        [node],
      );
    }
  }

  // Both must be composite; an unknown or non-composite type is left to
  // the other rules.
  bool _cannotOverlap(SchemaType? fragmentType, SchemaType? parentType) =>
      fragmentType != null &&
      parentType != null &&
      fragmentType.isCompositeType &&
      parentType.isCompositeType &&
      !context.schema.typesOverlap(fragmentType, parentType);
}
