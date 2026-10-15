import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/selection_set.dart';
import '../../language/ast/type_ref.dart';
import '../../language/printer/printer.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.3.3 "Leaf Field Selections": a field of a scalar or enum type
/// has no selection, and a field of any other type has one that is not
/// empty (`GQL207`).
///
/// {@category validation}
final class const ScalarLeafsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) => _ScalarLeafs(context);
}

final class _ScalarLeafs(final ValidationContext context) extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is Field) {
      if (context.typeInfo.type case final type?) {
        _check(node, type);
      }
    }
    return .next;
  }

  void _check(Field field, TypeRef type) {
    final name = field.name.value;
    final typeText = const Printer().print(type);
    final isLeaf = context.schema.namedTypeOf(type)?.isLeafType ?? false;
    switch (field.selectionSet) {
      case final selection? when isLeaf:
        context.report(
          .scalarLeafs,
          'Field "$name" must not have a selection since type "$typeText" '
          'has no subfields.',
          [selection],
        );
      case null when !isLeaf:
        context.report(
          .scalarLeafs,
          'Field "$name" of type "$typeText" must have a selection of '
          'subfields. Did you mean "$name { ... }"?',
          [field],
        );
      case SelectionSet(selections: []) when !isLeaf:
        context.report(
          .scalarLeafs,
          'Field "$name" of type "$typeText" must have at least one field '
          'selected.',
          [field],
        );
      default:
    }
  }
}
