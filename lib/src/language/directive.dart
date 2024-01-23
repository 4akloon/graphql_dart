import 'package:graphql_dart/src/language/abstract_node.dart';
import 'package:graphql_dart/src/language/named_node.dart';
import 'package:graphql_dart/src/language/node.dart';
import 'package:graphql_dart/src/language/node_children_container.dart';
import 'package:graphql_dart/src/language/node_visitor.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';
import 'package:graphql_dart/src/util/traverser_context.dart';

import '../util/consumer.dart';
import '../util/node_util.dart';
import 'argument.dart';
import 'ignored_chars.dart';
import 'node_builder.dart';

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
  List<Argument> _arguments = [];

  DirectiveBuilder._(this.name);

  DirectiveBuilder._from(Directive directive)
      : name = directive.name,
        _arguments = directive.arguments,
        super(
          sourceLocation: directive.sourceLocation,
          comments: directive.comments,
          ignoredChars: directive.ignoredChars,
          additionalData: directive.additionalData,
        );

  set arguments(List<Argument> arguments) {
    _arguments = List.unmodifiable(arguments);
  }

  set argument(Argument argument) {
    _arguments = List.unmodifiable([..._arguments, argument]);
  }

  Directive build() => Directive._(
        name: name,
        arguments: _arguments,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
