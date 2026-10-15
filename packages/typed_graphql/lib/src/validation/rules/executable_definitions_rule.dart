import '../../language/ast/definition.dart';
import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/type_system_definition.dart';
import '../../language/ast/type_system_extension.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.1.1 "Executable Definitions": a document sent for execution
/// holds only operations and fragments (`GQL200`).
///
/// {@category validation}
final class const ExecutableDefinitionsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _ExecutableDefinitions(context);
}

final class _ExecutableDefinitions(final ValidationContext context)
    extends AstVisitor {
  @override
  VisitAction enter(Node node) {
    if (node is! Document) {
      return .next;
    }
    for (final definition in node.definitions) {
      if (definition is ExecutableDefinition) {
        continue;
      }
      context.report(
        .executableDefinitions,
        'The ${_described(definition)} definition is not executable.',
        [definition],
      );
    }
    return .skip;
  }

  static String _described(Definition definition) => switch (definition) {
    SchemaDefinition() || SchemaExtension() => 'schema',
    DirectiveDefinition(:final name) ||
    TypeDefinition(:final name) ||
    DirectiveExtension(:final name) ||
    TypeExtension(:final name) => '"${name.value}"',
    _ => throw ArgumentError.value(
      definition,
      'definition',
      'is not a GraphQL definition',
    ),
  };
}
