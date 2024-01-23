import '../util/consumer.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_described_node.dart';
import 'description.dart';
import 'directive_location.dart';
import 'input_value_definition.dart';
import 'named_node.dart';
import 'node.dart';
import 'node_builder.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';
import 'sdl_named_definition.dart';

class DirectiveDefinition extends AbstractDescribedNode<DirectiveDefinition>
    implements
        SDLNamedDefinition<DirectiveDefinition>,
        NamedNode<DirectiveDefinition> {
  static const String childInputValueDefinitions = 'inputValueDefinitions';
  static const String childDirectiveLocation = 'directiveLocation';

  @override
  final String name;
  final bool repeatable;
  final List<InputValueDefinition> inputValueDefinitions;
  final List<DirectiveLocation> directiveLocations;

  DirectiveDefinition._({
    required this.name,
    required this.repeatable,
    super.description,
    List<InputValueDefinition> inputValueDefinitions = const [],
    List<DirectiveLocation> directiveLocations = const [],
    super.sourceLocation,
    super.comments = const [],
    super.ignoredChars,
    Map<String, String> additionalData = const {},
  })  : inputValueDefinitions = List.unmodifiable(inputValueDefinitions),
        directiveLocations = List.unmodifiable(directiveLocations),
        super(
          additionalData: additionalData,
        );

  @override
  List<Node> get children => [
        ...inputValueDefinitions,
        ...directiveLocations,
      ];

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .children(childInputValueDefinitions, inputValueDefinitions)
      .children(childDirectiveLocation, directiveLocations)
      .build();

  @override
  DirectiveDefinition withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) => builder
        ..inputValueDefinitions =
            newChildren.getChildrenValue(childInputValueDefinitions)
        ..directiveLocations =
            newChildren.getChildrenValue(childDirectiveLocation),
    );
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is DirectiveDefinition) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  DirectiveDefinition deepCopy() => DirectiveDefinition._(
        name: name,
        repeatable: repeatable,
        description: description,
        inputValueDefinitions: deepCopyFromNodes(inputValueDefinitions) ?? [],
        directiveLocations: deepCopyFromNodes(directiveLocations) ?? [],
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );

  @override
  String toString() =>
      'DirectiveDefinition(name: $name, repeatable: $repeatable, inputValueDefinitions: $inputValueDefinitions, directiveLocations: $directiveLocations)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitDirectiveDefinition(this, context);
  }

  static DirectiveDefinitionBuilder builder(String name) =>
      DirectiveDefinitionBuilder._(name);

  DirectiveDefinition transform(
      Consumer<DirectiveDefinitionBuilder> builderConsumer) {
    final builder = DirectiveDefinitionBuilder._from(this);
    builderConsumer(builder);
    return builder.build();
  }
}

final class DirectiveDefinitionBuilder extends NodeBuilder {
  String name;
  bool repeatable;
  Description? description;
  List<InputValueDefinition> inputValueDefinitions;
  List<DirectiveLocation> directiveLocations;

  DirectiveDefinitionBuilder._(this.name)
      : repeatable = false,
        inputValueDefinitions = [],
        directiveLocations = [];

  DirectiveDefinitionBuilder._from(DirectiveDefinition directiveDefinition)
      : name = directiveDefinition.name,
        repeatable = directiveDefinition.repeatable,
        description = directiveDefinition.description,
        inputValueDefinitions = directiveDefinition.inputValueDefinitions,
        directiveLocations = directiveDefinition.directiveLocations,
        super(
          sourceLocation: directiveDefinition.sourceLocation,
          comments: directiveDefinition.comments,
          ignoredChars: directiveDefinition.ignoredChars,
          additionalData: directiveDefinition.additionalData,
        );

  set inputValueDefinition(InputValueDefinition inputValueDefinition) {
    inputValueDefinitions =
        List.unmodifiable([...inputValueDefinitions, inputValueDefinition]);
  }

  set directiveLocation(DirectiveLocation directiveLocation) {
    directiveLocations =
        List.unmodifiable([...directiveLocations, directiveLocation]);
  }

  DirectiveDefinition build() => DirectiveDefinition._(
        name: name,
        repeatable: repeatable,
        description: description,
        inputValueDefinitions: inputValueDefinitions,
        directiveLocations: directiveLocations,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
