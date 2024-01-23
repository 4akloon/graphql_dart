import 'package:graphql_dart/src/language/abstract_node.dart';
import 'package:graphql_dart/src/language/directives_container.dart';
import 'package:graphql_dart/src/language/named_node.dart';
import 'package:graphql_dart/src/language/node_visitor.dart';
import 'package:graphql_dart/src/language/selection.dart';
import 'package:graphql_dart/src/language/selection_set_container.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';
import 'package:graphql_dart/src/util/traverser_context.dart';

import '../util/consumer.dart';
import 'argument.dart';
import 'directive.dart';
import 'node.dart';
import 'node_children_container.dart';
import 'node_directives_builder.dart';
import 'selection_set.dart';

class Field extends AbstractNode<Field>
    with DirectivesContainer<Field>
    implements
        Selection<Field>,
        SelectionSetContainer<Field>,
        NamedNode<Field> {
  static const String childArguments = 'arguments';
  static const String childDirectives = 'directives';
  static const String childSelectionSet = 'selectionSet';

  @override
  final String name;
  final String? alias;
  final List<Argument> arguments;
  @override
  final List<Directive> directives;
  @override
  final SelectionSet? selectionSet;

  Field._({
    required this.name,
    this.alias,
    List<Argument> arguments = const [],
    List<Directive> directives = const [],
    this.selectionSet,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  })  : arguments = List.unmodifiable(arguments),
        directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
        ...arguments,
        ...directives,
        if (selectionSet != null) selectionSet!,
      ];

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .children(childArguments, arguments)
      .children(childDirectives, directives)
      .child(childSelectionSet, selectionSet)
      .build();

  @override
  Field withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) => builder
        ..arguments = newChildren.getChildrenValue(childArguments)
        ..directives = newChildren.getChildrenValue(childDirectives)
        ..selectionSet = newChildren.getChild(childSelectionSet),
    );
  }

  String get resultKey => alias ?? name;

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is Field) {
      return name == node.name && alias == node.alias;
    } else {
      return false;
    }
  }

  @override
  Field deepCopy() => Field._(
        name: name,
        alias: alias,
        arguments: deepCopyFromNodes(arguments) ?? [],
        directives: deepCopyFromNodes(directives) ?? [],
        selectionSet: deepCopyFromNode(selectionSet),
        sourceLocation: sourceLocation,
        comments: comments,
        additionalData: additionalData,
        ignoredChars: ignoredChars,
      );

  @override
  String toString() =>
      'Field(name: $name, alias: $alias, arguments: $arguments, directives: $directives, selectionSet: $selectionSet)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitField(this, context);
  }

  static FieldBuilder builder(String name) => FieldBuilder._(name);

  Field transform(Consumer<FieldBuilder> buildConsumer) {
    final builder = FieldBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class FieldBuilder extends NodeDirectivesBuilder {
  String name;
  String? alias;
  List<Argument> arguments;
  SelectionSet? selectionSet;

  FieldBuilder._(this.name) : arguments = [];

  FieldBuilder._from(Field field)
      : name = field.name,
        alias = field.alias,
        arguments = field.arguments,
        selectionSet = field.selectionSet,
        super(
          directives: field.directives,
          sourceLocation: field.sourceLocation,
          comments: field.comments,
          ignoredChars: field.ignoredChars,
          additionalData: field.additionalData,
        );

  set argument(Argument argument) {
    arguments = [...arguments, argument];
  }

  Field build() => Field._(
        name: name,
        alias: alias,
        arguments: arguments,
        directives: directives,
        selectionSet: selectionSet,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
