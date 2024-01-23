import 'package:graphql_dart/src/language/abstract_node.dart';
import 'package:graphql_dart/src/language/node_children_container.dart';
import 'package:graphql_dart/src/language/node_visitor.dart';
import 'package:graphql_dart/src/language/type.dart';
import 'package:graphql_dart/src/util/consumer.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';
import 'package:graphql_dart/src/util/traverser_context.dart';

import 'node.dart';
import 'node_builder.dart';

class ListType extends AbstractNode<ListType> implements GType<ListType> {
  static const String childType = 'type';

  final GType type;

  ListType._({
    required this.type,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  });

  @override
  List<Node> get children => List.unmodifiable([type]);

  @override
  NodeChildrenContainer get namedChildren =>
      NodeChildrenContainer.builder().child(childType, type).build();

  @override
  ListType withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) {
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
    } else {
      return true;
    }
  }

  @override
  ListType deepCopy() => ListType._(
        type: deepCopyFromNode(type)!,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );

  @override
  String toString() => 'ListType(type: $type)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitListType(this, context);
  }

  static ListTypeBuilder builder(GType type) => ListTypeBuilder._(type);

  factory ListType.of(GType type) => builder(type).build();

  ListType transform(Consumer<ListTypeBuilder> buildConsumer) {
    final builder = ListTypeBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class ListTypeBuilder extends NodeBuilder {
  GType type;

  ListTypeBuilder._(this.type);

  ListTypeBuilder._from(ListType existing)
      : type = existing.type,
        super(
          sourceLocation: existing.sourceLocation,
          comments: existing.comments,
          ignoredChars: existing.ignoredChars,
          additionalData: existing.additionalData,
        );

  ListType build() {
    return ListType._(
      type: type,
      sourceLocation: sourceLocation,
      comments: comments,
      ignoredChars: ignoredChars,
      additionalData: additionalData,
    );
  }
}
