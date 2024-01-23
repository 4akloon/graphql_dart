import '../util/consumer.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_node.dart';
import 'ignored_chars.dart';
import 'named_node.dart';
import 'node.dart';
import 'node_builder.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';
import 'value.dart';

class Argument extends AbstractNode<Argument> implements NamedNode<Argument> {
  static const String childValue = 'value';

  @override
  final String name;
  final Value? value;

  Argument._({
    required this.name,
    required this.value,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    IgnoredChars? ignoredChars,
  }) : super(ignoredChars: ignoredChars ?? IgnoredChars.empty());

  static ArgumentBuilder builder({
    required String name,
    Value? value,
  }) =>
      ArgumentBuilder._(name, value);

  @override
  List<Node> get children => value == null ? [] : [value!];

  @override
  NodeChildrenContainer get namedChildren =>
      NodeChildrenContainer.builder().child(childValue, value).build();

  @override
  Argument withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) => builder.value = newChildren.getChild(childValue),
    );
  }

  @override
  bool isEqualTo(Node? node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node?.runtimeType) {
      return false;
    } else if (node is Argument) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  Argument deepCopy() {
    return Argument._(
      name: name,
      value: deepCopyFromNode(value),
      sourceLocation: sourceLocation,
      comments: comments,
      ignoredChars: ignoredChars,
      additionalData: additionalData,
    );
  }

  @override
  String toString() => 'Argument(name: $name, value: $value)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitArgument(this, context);
  }

  Argument transform(Consumer<ArgumentBuilder> builderConsumer) {
    final builder = ArgumentBuilder._from(this);
    builderConsumer(builder);
    return builder.build();
  }
}

final class ArgumentBuilder extends NodeBuilder {
  String name;
  Value? value;

  ArgumentBuilder._(this.name, this.value);

  ArgumentBuilder._from(Argument argument)
      : name = argument.name,
        value = argument.value,
        super(
          sourceLocation: argument.sourceLocation,
          comments: argument.comments,
          ignoredChars: argument.ignoredChars,
          additionalData: argument.additionalData,
        );

  Argument build() => Argument._(
        name: name,
        value: value,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
