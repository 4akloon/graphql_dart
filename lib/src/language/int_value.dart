import 'package:graphql_dart/src/language/abstract_node.dart';
import 'package:graphql_dart/src/language/node_children_container.dart';
import 'package:graphql_dart/src/language/scalar_value.dart';
import 'package:graphql_dart/src/util/consumer.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';

import '../util/node_util.dart';
import '../util/traverser_context.dart';
import 'node.dart';
import 'node_builder.dart';
import 'node_visitor.dart';

class IntValue extends AbstractNode<IntValue> implements ScalarValue<IntValue> {
  final int value;

  IntValue._({
    required this.value,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  });

  @override
  List<Node> get children => const [];

  @override
  NodeChildrenContainer get namedChildren =>
      NodeChildrenContainer.builder().build();

  @override
  IntValue withNewChildren(NodeChildrenContainer newChildren) {
    NodeUtil.assertNewChildrenAreEmpty(newChildren);
    return this;
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is IntValue) {
      return value == node.value;
    } else {
      return false;
    }
  }

  @override
  IntValue deepCopy() => IntValue._(
        value: value,
        ignoredChars: ignoredChars,
        comments: comments,
        additionalData: additionalData,
        sourceLocation: sourceLocation,
      );

  @override
  String toString() => 'IntValue(value: $value)';

  factory IntValue.of(int value) => builder(value).build();

  static IntValueBuilder builder(int value) => IntValueBuilder._(value);

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitIntValue(this, context);
  }

  IntValue transform(Consumer<IntValueBuilder> builderConsumer) {
    final builder = IntValueBuilder._from(this);
    builderConsumer(builder);
    return builder.build();
  }
}

final class IntValueBuilder extends NodeBuilder {
  int value;

  IntValueBuilder._(this.value);

  IntValueBuilder._from(IntValue intValue)
      : value = intValue.value,
        super(
          sourceLocation: intValue.sourceLocation,
          comments: intValue.comments,
          ignoredChars: intValue.ignoredChars,
          additionalData: intValue.additionalData,
        );

  IntValue build() => IntValue._(
        value: value,
        ignoredChars: ignoredChars,
        comments: comments,
        additionalData: additionalData,
        sourceLocation: sourceLocation,
      );
}
