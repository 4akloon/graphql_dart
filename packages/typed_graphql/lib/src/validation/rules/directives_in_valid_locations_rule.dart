import '../../language/ast/directive.dart';
import '../../language/ast/directive_location.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/node.dart';
import '../../language/ast/operation_type.dart';
import '../../language/ast/selection.dart';
import '../../language/ast/variable_definition.dart';
import '../../language/visitor/ast_visitor.dart';
import '../../language/visitor/visit_action.dart';
import '../validation_context.dart';
import '../validation_rule.dart';

/// Spec §5.7.2 "Directives Are In Valid Locations": a directive is applied
/// only where its definition allows (`GQL223`).
///
/// This is the second half of graphql-js's `KnownDirectivesRule`; a
/// directive the schema does not define is left to `KnownDirectivesRule`.
/// Only executable locations are known: a type system definition in an
/// executable document is reported by `ExecutableDefinitionsRule`.
///
/// {@category validation}
final class const DirectivesInValidLocationsRule() extends ValidationRule {
  /// Creates the rule.
  this;

  @override
  AstVisitor createVisitor(ValidationContext context) =>
      _DirectivesInValidLocations(context);
}

final class _DirectivesInValidLocations(final ValidationContext context)
    extends AstVisitor {
  // The nodes entered and not yet left; a directive's parent is the top.
  final List<Node> _ancestors = [];

  @override
  VisitAction enter(Node node) {
    if (node case Directive(:final name) when _ancestors.isNotEmpty) {
      _check(node, name.value, _locationOf(_ancestors.last));
    }
    _ancestors.add(node);
    return .next;
  }

  @override
  void leave(Node node) {
    _ancestors.removeLast();
  }

  void _check(Directive node, String name, DirectiveLocation? location) {
    final definition = context.schema.directiveNamed(name);
    if (definition == null ||
        location == null ||
        definition.locations.contains(location)) {
      return;
    }
    context.report(
      .directivesInValidLocations,
      'Directive "@$name" may not be used on ${location.spelling}.',
      [node],
    );
  }

  DirectiveLocation? _locationOf(Node parent) => switch (parent) {
    OperationDefinition(:final operation) => switch (operation) {
      OperationType.query => .query,
      OperationType.mutation => .mutation,
      OperationType.subscription => .subscription,
    },
    Field() => .field,
    FragmentSpread() => .fragmentSpread,
    InlineFragment() => .inlineFragment,
    FragmentDefinition() => .fragmentDefinition,
    VariableDefinition() => .variableDefinition,
    _ => null,
  };
}
