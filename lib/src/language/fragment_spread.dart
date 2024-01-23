import 'package:graphql_dart/src/language/abstract_node.dart';
import 'package:graphql_dart/src/language/directives_container.dart';
import 'package:graphql_dart/src/language/named_node.dart';
import 'package:graphql_dart/src/language/node_visitor.dart';
import 'package:graphql_dart/src/language/selection.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';
import 'package:graphql_dart/src/util/traverser_context.dart';

import '../util/consumer.dart';
import 'directive.dart';
import 'node.dart';
import 'node_children_container.dart';
import 'node_directives_builder.dart';

class FragmentSpread extends AbstractNode<FragmentSpread>
    with DirectivesContainer<FragmentSpread>
    implements Selection<FragmentSpread>, NamedNode<FragmentSpread> {
  static const String childDirectives = 'directives';

  @override
  final String name;
  @override
  final List<Directive> directives;

  FragmentSpread._({
    required this.name,
    List<Directive> directives = const [],
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  }) : directives = List.unmodifiable(directives);

  @override
  List<Node> get children => List.unmodifiable(directives);

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .children(childDirectives, directives)
      .build();

  @override
  FragmentSpread withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) =>
          builder.directives = newChildren.getChildrenValue(childDirectives),
    );
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is FragmentSpread) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  FragmentSpread deepCopy() => FragmentSpread._(
        name: name,
        directives: deepCopyFromNodes<Directive>(directives) ?? [],
        ignoredChars: ignoredChars,
        comments: comments,
        additionalData: additionalData,
        sourceLocation: sourceLocation,
      );

  @override
  String toString() => 'FragmentSpread(name: $name, directives: $directives)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitFragmentSpread(this, context);
  }

  static FragmentSpreadBuilder builder(String name) =>
      FragmentSpreadBuilder._(name);

  FragmentSpread transform(Consumer<FragmentSpreadBuilder> builderConsumer) {
    final builder = FragmentSpreadBuilder._from(this);
    builderConsumer(builder);
    return builder.build();
  }
}

final class FragmentSpreadBuilder extends NodeDirectivesBuilder {
  String name;

  FragmentSpreadBuilder._(this.name);

  FragmentSpreadBuilder._from(FragmentSpread fragmentSpread)
      : name = fragmentSpread.name,
        super(
          directives: fragmentSpread.directives,
          sourceLocation: fragmentSpread.sourceLocation,
          comments: fragmentSpread.comments,
          additionalData: fragmentSpread.additionalData,
          ignoredChars: fragmentSpread.ignoredChars,
        );

  FragmentSpread build() {
    return FragmentSpread._(
      name: name,
      directives: directives,
      sourceLocation: sourceLocation,
      comments: comments,
      additionalData: additionalData,
      ignoredChars: ignoredChars,
    );
  }
}
