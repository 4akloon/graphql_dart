import '../util/consumer.dart';
import '../util/node_util.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_node.dart';
import 'named_node.dart';
import 'node.dart';
import 'node_builder.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';
import 'value.dart';

class EnumValue extends AbstractNode<EnumValue>
    implements Value<EnumValue>, NamedNode<EnumValue> {
  @override
  final String name;

  EnumValue._({
    required this.name,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  });

  EnumValue(String name) : this._(name: name);

  EnumValue.of(String name) : this(name);

  @override
  List<Node> get children => [];

  @override
  NodeChildrenContainer get namedChildren =>
      NodeChildrenContainer.builder().build();

  @override
  EnumValue withNewChildren(NodeChildrenContainer newChildren) {
    NodeUtil.assertNewChildrenAreEmpty(newChildren);
    return this;
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is EnumValue) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  EnumValue deepCopy() => EnumValue._(
        name: name,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );

  @override
  String toString() => 'EnumValue(name: $name)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitEnumValue(this, context);
  }

  static EnumValueBuilder builder(String name) => EnumValueBuilder._(name);

  EnumValue transform(Consumer<EnumValueBuilder> builderConsumer) {
    final builder = EnumValueBuilder._from(this);
    builderConsumer(builder);
    return builder.build();
  }
}

final class EnumValueBuilder extends NodeBuilder {
  String name;

  EnumValueBuilder._(this.name);

  EnumValueBuilder._from(EnumValue existing)
      : name = existing.name,
        super(
          sourceLocation: existing.sourceLocation,
          comments: existing.comments,
          ignoredChars: existing.ignoredChars,
          additionalData: existing.additionalData,
        );

  EnumValue build() {
    return EnumValue._(
      name: name,
      sourceLocation: sourceLocation,
      comments: comments,
      ignoredChars: ignoredChars,
      additionalData: additionalData,
    );
  }
}
