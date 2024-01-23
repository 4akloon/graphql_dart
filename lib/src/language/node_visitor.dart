import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'argument.dart';
import 'array_value.dart';
import 'boolean_value.dart';
import 'directive.dart';
import 'directive_definition.dart';
import 'directive_location.dart';
import 'document.dart';
import 'enum_type_definition.dart';
import 'enum_value.dart';
import 'enum_value_definition.dart';
import 'field.dart';
import 'field_definition.dart';
import 'float_value.dart';
import 'fragment_definition.dart';
import 'fragment_spread.dart';
import 'input_value_definition.dart';
import 'node.dart';
import 'operation_definition.dart';
import 'selection_set.dart';
import 'type_name.dart';
import 'variable_definition.dart';

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

  TraversalControl visitDocument(
    Document node,
    TraverserContext<Node> data,
  );

  TraversalControl visitEnumTypeDefinition(
    EnumTypeDefinition node,
    TraverserContext<Node> data,
  );

  TraversalControl visitEnumValue(
    EnumValue node,
    TraverserContext<Node> data,
  );

  TraversalControl visitEnumValueDefinition(
    EnumValueDefinition node,
    TraverserContext<Node> data,
  );

  TraversalControl visitField(
    Field node,
    TraverserContext<Node> data,
  );

  TraversalControl visitFieldDefinition(
    FieldDefinition node,
    TraverserContext<Node> data,
  );

  TraversalControl visitFloatValue(
    FloatValue node,
    TraverserContext<Node> data,
  );

  TraversalControl visitFragmentDefinition(
    FragmentDefinition node,
    TraverserContext<Node> data,
  );

  TraversalControl visitFragmentSpread(
    FragmentSpread node,
    TraverserContext<Node> data,
  );

  TraversalControl visitOperationDefinition(
    OperationDefinition node,
    TraverserContext<Node> data,
  );

  TraversalControl visitSelectionSet(
    SelectionSet node,
    TraverserContext<Node> data,
  );

  TraversalControl visitTypeName(
    TypeName node,
    TraverserContext<Node> data,
  );

  TraversalControl visitVariableDefinition(
    VariableDefinition node,
    TraverserContext<Node> data,
  );
}
