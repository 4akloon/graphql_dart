import '../util/consumer.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_described_node.dart';
import 'description.dart';
import 'directive.dart';
import 'directives_container.dart';
import 'named_node.dart';
import 'node.dart';
import 'node_children_container.dart';
import 'node_directives_builder.dart';
import 'node_visitor.dart';
import 'type.dart';
import 'value.dart';

class InputValueDefinition extends AbstractDescribedNode<InputValueDefinition>
    with DirectivesContainer<InputValueDefinition>
    implements NamedNode<InputValueDefinition> {
  static const String childType = 'type';
  static const String childDefaultValue = 'defaultValue';
  static const String childDirectives = 'directives';

  @override
  final String name;
  final GType type;
  final Value? defaultValue;
  @override
  final List<Directive> directives;

  InputValueDefinition._({
    required this.name,
    required this.type,
    this.defaultValue,
    List<Directive> directives = const [],
    super.description,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  }) : directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
        type,
        if (defaultValue != null) defaultValue!,
        ...directives,
      ];

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .child(childType, type)
      .child(childDefaultValue, defaultValue)
      .children(childDirectives, directives)
      .build();

  @override
  InputValueDefinition withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) {
        builder
          ..defaultValue = newChildren.getChild(childDefaultValue)
          ..directives = newChildren.getChildrenValue(childDirectives);

        final type = newChildren.getChild(childType);

        if (type is GType) {
          builder.type = type;
        }
      },
    );
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is InputValueDefinition) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  InputValueDefinition deepCopy() => InputValueDefinition._(
        name: name,
        type: deepCopyFromNode(type)!,
        defaultValue: deepCopyFromNode(defaultValue),
        directives: deepCopyFromNodes<Directive>(directives) ?? [],
        description: description,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );

  @override
  String toString() =>
      'InputValueDefinition(name: $name, type: $type, defaultValue: $defaultValue, directives: $directives)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitInputValueDefinition(this, context);
  }

  static InputValueDefinitionBuilder builder({
    required String name,
    required GType type,
  }) =>
      InputValueDefinitionBuilder._(name, type);

  InputValueDefinition transform(
      Consumer<InputValueDefinitionBuilder> buildConsumer) {
    final builder = InputValueDefinitionBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class InputValueDefinitionBuilder extends NodeDirectivesBuilder {
  String name;
  GType type;
  Value? defaultValue;
  Description? description;

  InputValueDefinitionBuilder._(this.name, this.type);

  InputValueDefinitionBuilder._from(InputValueDefinition inputValueDefinition)
      : name = inputValueDefinition.name,
        type = inputValueDefinition.type,
        defaultValue = inputValueDefinition.defaultValue,
        description = inputValueDefinition.description,
        super(
          sourceLocation: inputValueDefinition.sourceLocation,
          comments: inputValueDefinition.comments,
          ignoredChars: inputValueDefinition.ignoredChars,
          additionalData: inputValueDefinition.additionalData,
          directives: inputValueDefinition.directives,
        );

  InputValueDefinition build() => InputValueDefinition._(
        name: name,
        type: type,
        defaultValue: defaultValue,
        description: description,
        directives: directives,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
