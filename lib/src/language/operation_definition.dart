import '../util/consumer.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_node.dart';
import 'definition.dart';
import 'directive.dart';
import 'directives_container.dart';
import 'node.dart';
import 'node_builder.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';
import 'selection_set.dart';
import 'selection_set_container.dart';
import 'variable_definition.dart';

enum Operation {
  query,
  mutation,
  subscription,
}

class OperationDefinition extends AbstractNode<OperationDefinition>
    with DirectivesContainer<OperationDefinition>
    implements
        Definition<OperationDefinition>,
        SelectionSetContainer<OperationDefinition> {
  static const String childVariableDefinitions = 'variableDefinitions';
  static const String childDirectives = 'directives';
  static const String childSelectionSet = 'selectionSet';

  final String name;
  final Operation? operation;
  final List<VariableDefinition> variableDefinitions;
  @override
  final List<Directive> directives;
  @override
  final SelectionSet? selectionSet;

  OperationDefinition._({
    required this.name,
    this.operation,
    List<VariableDefinition> variableDefinitions = const [],
    List<Directive> directives = const [],
    this.selectionSet,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  })  : variableDefinitions = List.unmodifiable(variableDefinitions),
        directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
        ...variableDefinitions,
        ...directives,
        if (selectionSet != null) selectionSet!,
      ];

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .children(childVariableDefinitions, variableDefinitions)
      .children(childDirectives, directives)
      .child(childSelectionSet, selectionSet)
      .build();

  @override
  OperationDefinition withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) => builder
        ..variableDefinitions =
            newChildren.getChildrenValue(childVariableDefinitions)
        ..directives = newChildren.getChildrenValue(childDirectives)
        ..selectionSet = newChildren.getChild(childSelectionSet),
    );
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is OperationDefinition) {
      return name == node.name && operation == node.operation;
    } else {
      return false;
    }
  }

  @override
  OperationDefinition deepCopy() => OperationDefinition._(
        name: name,
        operation: operation,
        variableDefinitions:
            deepCopyFromNodes<VariableDefinition>(variableDefinitions) ?? [],
        directives: deepCopyFromNodes<Directive>(directives) ?? [],
        selectionSet: deepCopyFromNode(selectionSet),
        sourceLocation: sourceLocation,
        comments: comments,
        additionalData: additionalData,
        ignoredChars: ignoredChars,
      );

  @override
  String toString() =>
      'OperationDefinition(name: $name, operation: $operation, variableDefinitions: $variableDefinitions, directives: $directives, selectionSet: $selectionSet)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitOperationDefinition(this, context);
  }

  static OperationDefinitionBuilder builder(String name) =>
      OperationDefinitionBuilder._(name);

  OperationDefinition transform(
      Consumer<OperationDefinitionBuilder> buildConsumer) {
    final builder = OperationDefinitionBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

class OperationDefinitionBuilder extends NodeBuilder {
  String name;
  Operation? operation;
  List<VariableDefinition> variableDefinitions = [];
  List<Directive> directives = [];
  SelectionSet? selectionSet;

  OperationDefinitionBuilder._(this.name);

  OperationDefinitionBuilder._from(OperationDefinition operationDefinition)
      : name = operationDefinition.name,
        operation = operationDefinition.operation,
        variableDefinitions = operationDefinition.variableDefinitions,
        directives = operationDefinition.directives,
        selectionSet = operationDefinition.selectionSet,
        super(
          sourceLocation: operationDefinition.sourceLocation,
          comments: operationDefinition.comments,
          ignoredChars: operationDefinition.ignoredChars,
          additionalData: operationDefinition.additionalData,
        );

  set variableDefinition(VariableDefinition variableDefinition) {
    variableDefinitions = [...variableDefinitions, variableDefinition];
  }

  set directive(Directive directive) {
    directives = [...directives, directive];
  }

  OperationDefinition build() => OperationDefinition._(
        name: name,
        operation: operation,
        variableDefinitions: variableDefinitions,
        directives: directives,
        selectionSet: selectionSet,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
