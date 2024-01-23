import '../util/consumer.dart';
import '../util/node_util.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_node.dart';
import 'ignored_chars.dart';
import 'node.dart';
import 'node_builder.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';
import 'scalar_value.dart';

class BooleanValue extends AbstractNode<BooleanValue>
    implements ScalarValue<BooleanValue> {
  final bool value;

  BooleanValue({
    required this.value,
    super.sourceLocation,
    super.comments = const [],
    IgnoredChars? ignoredChars,
    super.additionalData = const {},
  }) : super(ignoredChars: ignoredChars ?? IgnoredChars.empty());

  @override
  List<Node> get children => const [];

  @override
  NodeChildrenContainer get namedChildren =>
      NodeChildrenContainer.builder().build();

  @override
  BooleanValue withNewChildren(NodeChildrenContainer newChildren) {
    NodeUtil.assertNewChildrenAreEmpty(newChildren);
    return this;
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else {
      return false;
    }
  }

  @override
  BooleanValue deepCopy() => BooleanValue(
        value: value,
        ignoredChars: ignoredChars,
        comments: comments,
        additionalData: additionalData,
        sourceLocation: sourceLocation,
      );

  @override
  String toString() => 'BooleanValue(value: $value)';

  factory BooleanValue.of(bool value) => builder(value).build();

  static BooleanValueBuilder builder(bool value) =>
      BooleanValueBuilder._(value);

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitBooleanValue(this, context);
  }

  BooleanValue transform(Consumer<BooleanValueBuilder> buildConsumer) {
    final builder = BooleanValueBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class BooleanValueBuilder extends NodeBuilder {
  bool value;

  BooleanValueBuilder._(this.value);

  BooleanValueBuilder._from(BooleanValue existing)
      : value = existing.value,
        super(
          sourceLocation: existing.sourceLocation,
          comments: existing.comments,
          ignoredChars: existing.ignoredChars,
          additionalData: existing.additionalData,
        );

  BooleanValue build() {
    return BooleanValue(
      value: value,
      sourceLocation: sourceLocation,
      comments: comments,
      ignoredChars: ignoredChars,
      additionalData: additionalData,
    );
  }
}
