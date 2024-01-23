import '../util/consumer.dart';
import '../util/node_util.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_node.dart';
import 'argument.dart';
import 'ignored_chars.dart';
import 'named_node.dart';
import 'node.dart';
import 'node_builder.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';

class Directive extends AbstractNode<Directive>
    implements NamedNode<Directive> {
  static const String childArguments = 'arguments';
  @override
  final String name;
  final List<Argument> arguments;

  Directive._({
    required this.name,
    List<Argument> arguments = const [],
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    IgnoredChars? ignoredChars,
  })  : arguments = List.unmodifiable(arguments),
        super(ignoredChars: ignoredChars ?? IgnoredChars.empty());

  Map<String, Argument> getArgumentsByName() {
    return NodeUtil.nodeByName(arguments);
  }

  @override
  List<Node> get children => List.unmodifiable(arguments);

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .children(childArguments, arguments)
      .build();

  @override
  Directive withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) =>
          builder.arguments = newChildren.getChildrenValue(childArguments),
    );
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is Directive) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  Directive deepCopy() => Directive._(
        name: name,
        arguments: deepCopyFromNodes<Argument>(arguments) ?? [],
        sourceLocation: sourceLocation,
        comments: comments,
        additionalData: additionalData,
        ignoredChars: ignoredChars,
      );

  @override
  String toString() => 'Directive(name: $name, arguments: $arguments)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitDirective(this, context);
  }

  static DirectiveBuilder builder(String name) => DirectiveBuilder._(name);

  Directive transform(Consumer<DirectiveBuilder> buildConsumer) {
    final builder = DirectiveBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class DirectiveBuilder extends NodeBuilder {
  String name;
  List<Argument> arguments = [];

  DirectiveBuilder._(this.name);

  DirectiveBuilder._from(Directive directive)
      : name = directive.name,
        arguments = directive.arguments,
        super(
          sourceLocation: directive.sourceLocation,
          comments: directive.comments,
          ignoredChars: directive.ignoredChars,
          additionalData: directive.additionalData,
        );

  set argument(Argument argument) {
    arguments = [...arguments, argument];
  }

  Directive build() => Directive._(
        name: name,
        arguments: arguments,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
