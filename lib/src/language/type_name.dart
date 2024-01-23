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
import 'type.dart';

class TypeName extends AbstractNode<TypeName>
    implements GType<TypeName>, NamedNode<TypeName> {
  @override
  final String name;

  TypeName._({
    required this.name,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  });

  @override
  List<Node> get children => [];

  @override
  NodeChildrenContainer get namedChildren =>
      NodeChildrenContainer.builder().build();

  @override
  TypeName withNewChildren(NodeChildrenContainer newChildren) {
    NodeUtil.assertNewChildrenAreEmpty(newChildren);
    return this;
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is TypeName) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  TypeName deepCopy() => TypeName._(
        name: name,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );

  @override
  String toString() => 'TypeName(name: $name)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitTypeName(this, context);
  }

  static TypeNameBuilder builder(String name) => TypeNameBuilder._(name);

  TypeName transform(Consumer<TypeNameBuilder> builderConsumer) {
    final builder = TypeNameBuilder._from(this);
    builderConsumer(builder);
    return builder.build();
  }
}

final class TypeNameBuilder extends NodeBuilder {
  String name;

  TypeNameBuilder._(this.name);

  TypeNameBuilder._from(TypeName typeName)
      : name = typeName.name,
        super(
          sourceLocation: typeName.sourceLocation,
          comments: typeName.comments,
          ignoredChars: typeName.ignoredChars,
          additionalData: typeName.additionalData,
        );

  TypeName build() => TypeName._(
        name: name,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
