import '../../diagnostics/suggestions.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/value.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';
import 'list_size_setting.dart';

/// The IBM cost directives draft's operation rule (R3.8, `GQL237`): a field
/// whose `@listSize` has `slicingArguments` and keeps
/// `requireOneSlicingArgument` is given exactly one of them.
///
/// An argument counts when it is given a value other than the `null`
/// literal; a variable counts. The rule is opt-in: it is not one of the
/// specified rules.
///
/// {@category validation}
final class const SlicingArgumentsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _SlicingArguments(context);
}

final class _SlicingArguments(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is Field) {
      _check(node);
    }
    return .next;
  }

  void _check(Field field) {
    final definition = context.typeInfo.fieldDefinition;
    if (definition == null) {
      return;
    }
    final setting = ListSizeSetting.read(definition.appliedDirectives);
    if (setting == null ||
        setting.slicingArguments.isEmpty ||
        !setting.requiresOneSlicingArgument) {
      return;
    }
    final names = setting.slicingArguments;
    final given = {
      for (final argument in field.arguments)
        if (names.contains(argument.name.value) && argument.value is! NullValue)
          argument.name.value,
    }.length;
    if (given != 1) {
      final quoted = [for (final name in names) '"$name"'];
      context.report(
        .slicingArgumentsRequired,
        'Field "${field.name.value}" must be given exactly one of its '
        'slicing arguments ${const Suggestions().orList(quoted)}, but it was '
        'given $given.',
        [field],
      );
    }
  }
}
