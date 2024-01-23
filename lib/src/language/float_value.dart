import 'package:graphql_dart/src/language/abstract_node.dart';
import 'package:graphql_dart/src/language/node.dart';
import 'package:graphql_dart/src/language/node_visitor.dart';
import 'package:graphql_dart/src/language/scalar_value.dart';
import 'package:graphql_dart/src/util/consumer.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';
import 'package:graphql_dart/src/util/traverser_context.dart';

import '../util/node_util.dart';
import 'node_builder.dart';
import 'node_children_container.dart';

class FloatValue extends AbstractNode<FloatValue>
    implements ScalarValue<FloatValue> {
  final double value;

  FloatValue._({
    required this.value,
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
  FloatValue withNewChildren(NodeChildrenContainer newChildren) {
    NodeUtil.assertNewChildrenAreEmpty(newChildren);
    return this;
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is FloatValue) {
      return value == node.value;
    } else {
      return false;
    }
  }

  @override
  FloatValue deepCopy() => FloatValue._(
        value: value,
        ignoredChars: ignoredChars,
        comments: comments,
        additionalData: additionalData,
        sourceLocation: sourceLocation,
      );

  @override
  String toString() => 'FloatValue(value: $value)';

  factory FloatValue.of(double value) => builder(value).build();

  static FloatValueBuilder builder(double value) => FloatValueBuilder._(value);

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitFloatValue(this, context);
  }

  FloatValue transform(Consumer<FloatValueBuilder> buildConsumer) {
    final builder = FloatValueBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

class FloatValueBuilder extends NodeBuilder {
  double value;

  FloatValueBuilder._(this.value);

  FloatValueBuilder._from(FloatValue existing)
      : value = existing.value,
        super(
          sourceLocation: existing.sourceLocation,
          comments: existing.comments,
          ignoredChars: existing.ignoredChars,
          additionalData: existing.additionalData,
        );

  FloatValue build() => FloatValue._(
        value: value,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
