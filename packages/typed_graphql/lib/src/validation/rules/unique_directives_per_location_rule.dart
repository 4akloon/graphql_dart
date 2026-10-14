import '../../language/ast/directive.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/variable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.7.3 "Directives Are Unique Per Location": a directive that is
/// not repeatable is applied once at each location (`GQL224`).
///
/// The error points at the first use and relates to the repeat. A directive
/// the schema does not define is left to `KnownDirectivesRule`.
///
/// {@category validation}
final class const UniqueDirectivesPerLocationRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _UniqueDirectivesPerLocation(context);
}

final class _UniqueDirectivesPerLocation(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    final directives = switch (node) {
      OperationDefinition(:final directives) ||
      FragmentDefinition(:final directives) ||
      Field(:final directives) ||
      FragmentSpread(:final directives) ||
      InlineFragment(:final directives) ||
      VariableDefinition(:final directives) => directives,
      _ => const <Directive>[],
    };
    if (directives.length > 1) {
      _check(directives);
    }
    return .next;
  }

  void _check(List<Directive> directives) {
    final seen = <String, Directive>{};
    for (final directive in directives) {
      final name = directive.name.value;
      if (context.schema.directiveNamed(name)?.isRepeatable ?? true) {
        continue;
      }
      final first = seen[name];
      if (first == null) {
        seen[name] = directive;
      } else {
        context.report(
          .uniqueDirectivesPerLocation,
          'The directive "@$name" can only be used once at this location.',
          [first, directive],
        );
      }
    }
  }
}
