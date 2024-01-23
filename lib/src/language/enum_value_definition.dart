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

class EnumValueDefinition extends AbstractDescribedNode<EnumValueDefinition>
    with DirectivesContainer<EnumValueDefinition>
    implements NamedNode<EnumValueDefinition> {
  static const String childDirectives = 'directives';

  @override
  final String name;
  @override
  final List<Directive> directives;

  EnumValueDefinition._({
    required this.name,
    List<Directive> directives = const [],
    super.description,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  }) : directives = List.unmodifiable(directives);

  @override
  List<Node> get children => List.unmodifiable(directives);

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .children(childDirectives, directives)
      .build();

  @override
  EnumValueDefinition withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) =>
          builder..directives = newChildren.getChildrenValue(childDirectives),
    );
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is EnumValueDefinition) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  EnumValueDefinition deepCopy() => EnumValueDefinition._(
        name: name,
        directives: deepCopyFromNodes(directives) ?? [],
        description: description,
        sourceLocation: sourceLocation,
        comments: comments,
        additionalData: additionalData,
        ignoredChars: ignoredChars,
      );

  @override
  String toString() =>
      'EnumValueDefinition(name: $name, directives: $directives)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitEnumValueDefinition(this, context);
  }

  static EnumValueDefinitionBuilder builder(String name) =>
      EnumValueDefinitionBuilder._(name);

  EnumValueDefinition transform(
      Consumer<EnumValueDefinitionBuilder> buildConsumer) {
    final builder = EnumValueDefinitionBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class EnumValueDefinitionBuilder extends NodeDirectivesBuilder {
  String name;
  Description? description;

  EnumValueDefinitionBuilder._(this.name);

  EnumValueDefinitionBuilder._from(EnumValueDefinition existing)
      : name = existing.name,
        description = existing.description,
        super(
          directives: existing.directives,
          sourceLocation: existing.sourceLocation,
          comments: existing.comments,
          ignoredChars: existing.ignoredChars,
          additionalData: existing.additionalData,
        );

  EnumValueDefinition build() => EnumValueDefinition._(
        name: name,
        directives: directives,
        description: description,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
