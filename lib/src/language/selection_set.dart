import '../util/consumer.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_node.dart';
import 'node.dart';
import 'node_builder.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';
import 'selection.dart';

class SelectionSet extends AbstractNode<SelectionSet> {
  static const String childSelections = 'selections';

  final List<Selection> selections;

  SelectionSet._({
    List<Selection> selections = const [],
    super.sourceLocation,
    super.comments = const [],
    super.ignoredChars,
    super.additionalData = const {},
  }) : selections = List.unmodifiable(selections);

  List<T> getSelections<T extends Selection<dynamic>>() =>
      List.unmodifiable(selections.whereType<T>());

  @override
  List<Node> get children => List.unmodifiable(selections);

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .children(childSelections, selections)
      .build();

  @override
  SelectionSet withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) =>
          builder.selections = newChildren.getChildrenValue(childSelections),
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
  SelectionSet deepCopy() => SelectionSet._(
        selections: deepCopyFromNodes<Selection>(selections) ?? [],
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );

  @override
  String toString() => 'SelectionSet(selections: $selections)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitSelectionSet(this, context);
  }

  static SelectionSetBuilder builder(List<Selection> selections) =>
      SelectionSetBuilder._(selections);

  SelectionSet transform(Consumer<SelectionSetBuilder> buildConsumer) {
    final builder = SelectionSetBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class SelectionSetBuilder extends NodeBuilder {
  List<Selection> selections;

  SelectionSetBuilder._(this.selections);

  SelectionSetBuilder._from(SelectionSet selectionSet)
      : selections = selectionSet.selections,
        super(
          sourceLocation: selectionSet.sourceLocation,
          comments: selectionSet.comments,
          ignoredChars: selectionSet.ignoredChars,
          additionalData: selectionSet.additionalData,
        );

  SelectionSet build() => SelectionSet._(
        selections: selections,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
