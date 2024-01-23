import 'package:graphql_dart/src/language/abstract_node.dart';
import 'package:graphql_dart/src/language/named_node.dart';
import 'package:graphql_dart/src/language/node.dart';
import 'package:graphql_dart/src/language/node_builder.dart';
import 'package:graphql_dart/src/language/node_children_container.dart';
import 'package:graphql_dart/src/language/node_visitor.dart';
import 'package:graphql_dart/src/util/node_util.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';
import 'package:graphql_dart/src/util/traverser_context.dart';

import '../util/consumer.dart';
import 'ignored_chars.dart';

class DirectiveLocation extends AbstractNode<DirectiveLocation>
    implements NamedNode<DirectiveLocation> {
  @override
  final String name;

  DirectiveLocation._({
    required this.name,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    IgnoredChars? ignoredChars,
  }) : super(ignoredChars: ignoredChars ?? IgnoredChars.empty());

  @override
  List<Node<Node>> get children => [];

  @override
  NodeChildrenContainer get namedChildren =>
      NodeChildrenContainer.builder().build();

  @override
  DirectiveLocation withNewChildren(NodeChildrenContainer newChildren) {
    NodeUtil.assertNewChildrenAreEmpty(newChildren);
    return this;
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is DirectiveLocation) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  DirectiveLocation deepCopy() => DirectiveLocation._(
        name: name,
        ignoredChars: ignoredChars,
        comments: comments,
        additionalData: additionalData,
        sourceLocation: sourceLocation,
      );

  @override
  String toString() => 'DirectiveLocation(name: $name)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitDirectiveLocation(this, context);
  }

  static DirectiveLocationBuilder builder(String name) =>
      DirectiveLocationBuilder._(name);

  DirectiveLocation transform(
      Consumer<DirectiveLocationBuilder> builderConsumer) {
    final builder = DirectiveLocationBuilder._from(this);
    builderConsumer(builder);
    return builder.build();
  }
}

final class DirectiveLocationBuilder extends NodeBuilder {
  String name;

  DirectiveLocationBuilder._(this.name);

  DirectiveLocationBuilder._from(DirectiveLocation directiveLocation)
      : name = directiveLocation.name,
        super(
          sourceLocation: directiveLocation.sourceLocation,
          comments: directiveLocation.comments,
          ignoredChars: directiveLocation.ignoredChars,
          additionalData: directiveLocation.additionalData,
        );

  DirectiveLocation build() => DirectiveLocation._(
        name: name,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
