import '../util/consumer.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_described_node.dart';
import 'description.dart';
import 'directive.dart';
import 'directives_container.dart';
import 'input_value_definition.dart';
import 'named_node.dart';
import 'node.dart';
import 'node_children_container.dart';
import 'node_directives_builder.dart';
import 'node_visitor.dart';
import 'type.dart';

class FieldDefinition extends AbstractDescribedNode<FieldDefinition>
    with DirectivesContainer<FieldDefinition>
    implements NamedNode<FieldDefinition> {
  static const String childType = 'type';
  static const String childInputValueDefinition = 'inputValueDefinition';
  static const String childDirectives = 'directives';

  @override
  final String name;
  final GType? type;
  final List<InputValueDefinition> inputValueDefinitions;
  @override
  final List<Directive> directives;

  FieldDefinition._({
    required this.name,
    this.type,
    List<InputValueDefinition> inputValueDefinitions = const [],
    List<Directive> directives = const [],
    super.description,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  })  : inputValueDefinitions = List.unmodifiable(inputValueDefinitions),
        directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
        if (type != null) type!,
        ...inputValueDefinitions,
        ...directives,
      ];

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .child(childType, type)
      .children(childInputValueDefinition, inputValueDefinitions)
      .children(childDirectives, directives)
      .build();

  @override
  FieldDefinition withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) => builder
        ..type = newChildren.getChild(childType)
        ..inputValueDefinitions =
            newChildren.getChildrenValue(childInputValueDefinition)
        ..directives = newChildren.getChildrenValue(childDirectives),
    );
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is FieldDefinition) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  FieldDefinition deepCopy() => FieldDefinition._(
        name: name,
        type: deepCopyFromNode(type),
        inputValueDefinitions: deepCopyFromNodes(inputValueDefinitions) ?? [],
        directives: deepCopyFromNodes(directives) ?? [],
        description: description,
        sourceLocation: sourceLocation,
        comments: comments,
        additionalData: additionalData,
        ignoredChars: ignoredChars,
      );

  @override
  String toString() =>
      'FieldDefinition(name: $name, type: $type, inputValueDefinitions: $inputValueDefinitions, directives: $directives)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitFieldDefinition(this, context);
  }

  static FieldDefinitionBuilder builder(String name) =>
      FieldDefinitionBuilder._(name);

  FieldDefinition transform(Consumer<FieldDefinitionBuilder> buildConsumer) {
    final builder = FieldDefinitionBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class FieldDefinitionBuilder extends NodeDirectivesBuilder {
  String name;
  GType? type;
  Description? description;
  List<InputValueDefinition> inputValueDefinitions;

  FieldDefinitionBuilder._(this.name) : inputValueDefinitions = [];

  FieldDefinitionBuilder._from(FieldDefinition fieldDefinition)
      : name = fieldDefinition.name,
        type = fieldDefinition.type,
        description = fieldDefinition.description,
        inputValueDefinitions = fieldDefinition.inputValueDefinitions,
        super(
          directives: fieldDefinition.directives,
          sourceLocation: fieldDefinition.sourceLocation,
          comments: fieldDefinition.comments,
          ignoredChars: fieldDefinition.ignoredChars,
          additionalData: fieldDefinition.additionalData,
        );

  set inputValueDefinition(InputValueDefinition inputValueDefinition) {
    inputValueDefinitions = [...inputValueDefinitions, inputValueDefinition];
  }

  FieldDefinition build() => FieldDefinition._(
        name: name,
        type: type,
        inputValueDefinitions: inputValueDefinitions,
        directives: directives,
        description: description,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
