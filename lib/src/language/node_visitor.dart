import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'argument.dart';
import 'array_value.dart';
import 'boolean_value.dart';
import 'directive.dart';
import 'directive_definition.dart';
import 'directive_location.dart';
import 'input_value_definition.dart';
import 'node.dart';

abstract interface class NodeVisitor {
  TraversalControl visitArgument(
    Argument node,
    TraverserContext<Node> context,
  );

  TraversalControl visitArrayValue(
    ArrayValue node,
    TraverserContext<Node> context,
  );

  TraversalControl visitBooleanValue(
    BooleanValue node,
    TraverserContext<Node> context,
  );

  TraversalControl visitDirective(
    Directive node,
    TraverserContext<Node> context,
  );

  TraversalControl visitDirectiveDefinition(
    DirectiveDefinition node,
    TraverserContext<Node> context,
  );

  TraversalControl visitInputValueDefinition(
    InputValueDefinition node,
    TraverserContext<Node> context,
  );

  TraversalControl visitDirectiveLocation(
    DirectiveLocation node,
    TraverserContext<Node> context,
  );
}
