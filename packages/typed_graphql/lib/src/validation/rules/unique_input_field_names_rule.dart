import '../../language/ast/name.dart';
import '../../language/ast/node.dart';
import '../../language/ast/object_field.dart';
import '../../language/ast/value.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.6.3 "Input Object Field Uniqueness": an input object literal
/// gives each field once (`GQL220`).
///
/// The error points at the first name and at the repeat.
///
/// {@category validation}
final class const UniqueInputFieldNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueInputFieldNames(context);
}

final class _UniqueInputFieldNames(final ValidationContext context)
    extends AstVisitor {
  // One map of known names per object being walked, innermost last.
  final List<Map<String, Name>> _stack = [];

  @override
  VisitAction enter(Node node) {
    switch (node) {
      case ObjectValue():
        _stack.add({});
      case ObjectField(:final name):
        _check(name);
    }
    return .next;
  }

  @override
  void leave(Node node) {
    if (node is ObjectValue) {
      _stack.removeLast();
    }
  }

  void _check(Name name) {
    final known = _stack.last[name.value];
    if (known == null) {
      _stack.last[name.value] = name;
      return;
    }
    context.report(
      .uniqueInputFieldNames,
      'There can be only one input field named "${name.value}".',
      [known, name],
    );
  }
}
