import '../../diagnostics/suggestions.dart';
import '../../language/ast/argument.dart';
import '../../language/ast/directive.dart';
import '../../language/ast/node.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.4.1 "Argument Names": every argument names an argument of its
/// field or directive (`GQL208`).
///
/// A directive the schema does not define is left to `KnownDirectives`.
/// Unlike graphql-js, a directive definition inside the document is not
/// read: an executable document that holds one already fails
/// `ExecutableDefinitions`.
///
/// {@category validation}
final class const KnownArgumentNamesRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _KnownArgumentNames(context);
}

final class _KnownArgumentNames(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    switch (node) {
      case Directive():
        _checkDirective(node);
        return .skip;
      case Argument(:final name):
        _checkFieldArgument(node, name.value);
    }
    return .next;
  }

  void _checkFieldArgument(Argument node, String name) {
    final typeInfo = context.typeInfo;
    final field = typeInfo.fieldDefinition;
    final parent = typeInfo.parentType;
    if (typeInfo.argument != null || field == null || parent == null) {
      return;
    }
    final known = [for (final argument in field.arguments) argument.name];
    context.report(
      .knownArgumentNames,
      'Unknown argument "$name" on field "${parent.name}.${field.name}".'
      '${_suggestion(name, known)}',
      [node],
    );
  }

  void _checkDirective(Directive node) {
    final name = node.name.value;
    final definition = context.schema.directiveNamed(name);
    if (definition == null) {
      return;
    }
    final known = [for (final argument in definition.arguments) argument.name];
    for (final argument in node.arguments) {
      final argumentName = argument.name.value;
      if (!known.contains(argumentName)) {
        context.report(
          .knownArgumentNames,
          'Unknown argument "$argumentName" on directive "@$name".'
          '${_suggestion(argumentName, known)}',
          [argument],
        );
      }
    }
  }

  String _suggestion(String name, List<String> known) {
    if (!context.includesSuggestions) {
      return '';
    }
    const suggestions = Suggestions();
    return suggestions.didYouMean(suggestions.listFor(name, known));
  }
}
