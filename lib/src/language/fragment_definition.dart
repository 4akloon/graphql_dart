import '../util/consumer.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_node.dart';
import 'definition.dart';
import 'directive.dart';
import 'directives_container.dart';
import 'named_node.dart';
import 'node.dart';
import 'node_children_container.dart';
import 'node_directives_builder.dart';
import 'node_visitor.dart';
import 'selection_set.dart';
import 'selection_set_container.dart';
import 'type_name.dart';

class FragmentDefinition extends AbstractNode<FragmentDefinition>
    with DirectivesContainer<FragmentDefinition>
    implements
        Definition<FragmentDefinition>,
        SelectionSetContainer<FragmentDefinition>,
        NamedNode<FragmentDefinition> {
  static const String childTypeCondition = 'typeCondition';
  static const String childDirectives = 'directives';
  static const String childSelectionSet = 'selectionSet';

  @override
  final String name;
  final TypeName typeCondition;
  @override
  final List<Directive> directives;
  @override
  final SelectionSet? selectionSet;

  FragmentDefinition._({
    required this.name,
    required this.typeCondition,
    List<Directive> directives = const [],
    this.selectionSet,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  }) : directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
        typeCondition,
        ...directives,
        if (selectionSet != null) selectionSet!,
      ];

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .child(childTypeCondition, typeCondition)
      .children(childDirectives, directives)
      .child(childSelectionSet, selectionSet)
      .build();

  @override
  FragmentDefinition withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) {
        builder
          ..directives = newChildren.getChildrenValue(childDirectives)
          ..selectionSet = newChildren.getChild(childSelectionSet);

        final typeCondition = newChildren.getChild(childTypeCondition);

        if (typeCondition is TypeName) {
          builder.typeCondition = typeCondition;
        }
      },
    );
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is FragmentDefinition) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  FragmentDefinition deepCopy() => FragmentDefinition._(
        name: name,
        typeCondition: deepCopyFromNode(typeCondition)!,
        directives: deepCopyFromNodes(directives) ?? [],
        selectionSet: deepCopyFromNode(selectionSet),
        sourceLocation: sourceLocation,
        comments: comments,
        additionalData: additionalData,
        ignoredChars: ignoredChars,
      );

  @override
  String toString() =>
      'FragmentDefinition(name: $name, typeCondition: $typeCondition, directives: $directives, selectionSet: $selectionSet)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitFragmentDefinition(this, context);
  }

  static FragmentDefinitionBuilder builder(
    String name,
    TypeName typeCondition,
  ) =>
      FragmentDefinitionBuilder._(name, typeCondition);

  FragmentDefinition transform(
    Consumer<FragmentDefinitionBuilder> buildConsumer,
  ) {
    final builder = FragmentDefinitionBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class FragmentDefinitionBuilder extends NodeDirectivesBuilder {
  String name;
  TypeName typeCondition;
  SelectionSet? selectionSet;

  FragmentDefinitionBuilder._(this.name, this.typeCondition);

  FragmentDefinitionBuilder._from(FragmentDefinition fragmentDefinition)
      : name = fragmentDefinition.name,
        typeCondition = fragmentDefinition.typeCondition,
        selectionSet = fragmentDefinition.selectionSet,
        super(
          sourceLocation: fragmentDefinition.sourceLocation,
          comments: fragmentDefinition.comments,
          ignoredChars: fragmentDefinition.ignoredChars,
          additionalData: fragmentDefinition.additionalData,
          directives: fragmentDefinition.directives,
        );

  FragmentDefinition build() => FragmentDefinition._(
        name: name,
        typeCondition: typeCondition,
        directives: directives,
        selectionSet: selectionSet,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
