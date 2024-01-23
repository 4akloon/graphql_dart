import '../util/consumer.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_node.dart';
import 'ignored_chars.dart';
import 'node.dart';
import 'node_builder.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';
import 'value.dart';

class ArrayValue extends AbstractNode<ArrayValue> implements Value<ArrayValue> {
  static const String childValues = 'values';

  final List<Value> values;

  ArrayValue({
    required List<Value> values,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    IgnoredChars? ignoredChars,
  })  : values = List.unmodifiable(values),
        super(ignoredChars: ignoredChars ?? IgnoredChars.empty());

  static ArrayValueBuilder builder() => ArrayValueBuilder._([]);

  @override
  List<Node> get children => values;

  @override
  NodeChildrenContainer get namedChildren =>
      NodeChildrenContainer.builder().children(childValues, values).build();

  @override
  ArrayValue withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) => builder.values = newChildren.getChildrenValue(childValues),
    );
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
  String toString() => 'ArrayValue(values: $values)';

  @override
  ArrayValue deepCopy() => ArrayValue(
        values: deepCopyFromNodes<Value>(values) ?? [],
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitArrayValue(this, context);
  }

  ArrayValue transform(Consumer<ArrayValueBuilder> buildConsumer) {
    final builder = ArrayValueBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class ArrayValueBuilder extends NodeBuilder {
  List<Value> _values = [];

  ArrayValueBuilder._(List<Value> values) : _values = values;

  ArrayValueBuilder._from(ArrayValue arrayValue)
      : _values = List.unmodifiable(arrayValue.values),
        super(
          sourceLocation: arrayValue.sourceLocation,
          comments: arrayValue.comments,
          ignoredChars: arrayValue.ignoredChars,
          additionalData: arrayValue.additionalData,
        );

  set values(List<Value> values) {
    _values = List.unmodifiable(values);
  }

  set value(Value value) {
    _values = List.unmodifiable([..._values, value]);
  }

  ArrayValue build() => ArrayValue(
        values: _values,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
