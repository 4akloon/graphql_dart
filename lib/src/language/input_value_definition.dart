import 'package:graphql_dart/src/language/directive.dart';
import 'package:graphql_dart/src/language/node.dart';
import 'package:graphql_dart/src/language/node_children_container.dart';
import 'package:graphql_dart/src/language/node_visitor.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';
import 'package:graphql_dart/src/util/traverser_context.dart';

import '../util/consumer.dart';
import 'abstract_described_node.dart';
import 'directives_container.dart';
import 'ignored_chars.dart';
import 'named_node.dart';
import 'node_directives_builder.dart';
import 'type.dart';
import 'value.dart';

class InputValueDefinition extends AbstractDescribedNode<InputValueDefinition>
    with DirectivesContainer<InputValueDefinition>
    implements NamedNode<InputValueDefinition> {
  static const String childType = 'type';
  static const String childDefaultValue = 'defaultValue';
  static const String childDirectives = 'directives';

  @override
  final String name;
  final GType type;
  final Value? defaultValue;
  @override
  final List<Directive> directives;

  InputValueDefinition._({
    required this.name,
    required this.type,
    this.defaultValue,
    this.directives = const [],
    super.description,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    IgnoredChars? ignoredChars,
  }) : super(ignoredChars: ignoredChars ?? IgnoredChars.empty());

  @override
  List<Node> get children => [
        type,
        if (defaultValue != null) defaultValue!,
        ...directives,
      ];

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .child(childType, type)
      .child(childDefaultValue, defaultValue)
      .children(childDirectives, directives)
      .build();

  @override
  InputValueDefinition withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) => builder
        ..type = (newChildren.getChild(childType) as GType)
        ..defaultValue = newChildren.getChild(childDefaultValue)
        ..directives = newChildren.getChildrenValue(childDirectives),
    );
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is InputValueDefinition) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  InputValueDefinition deepCopy() => InputValueDefinition._(
        name: name,
        type: deepCopyFromNode(type)!,
        defaultValue: deepCopyFromNode(defaultValue),
        directives: deepCopyFromNodes<Directive>(directives) ?? [],
        description: description,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );

  @override
  String toString() =>
      'InputValueDefinition(name: $name, type: $type, defaultValue: $defaultValue, directives: $directives)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitInputValueDefinition(this, context);
  }

  static InputValueDefinitionBuilder builder({
    required String name,
    required GType type,
  }) =>
      InputValueDefinitionBuilder._(name, type);

  InputValueDefinition transform(
      Consumer<InputValueDefinitionBuilder> buildConsumer) {
    final builder = InputValueDefinitionBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class InputValueDefinitionBuilder extends NodeDirectivesBuilder {
  String name;
  GType type;
  Value? defaultValue;

  InputValueDefinitionBuilder._(this.name, this.type);

  InputValueDefinitionBuilder._from(InputValueDefinition inputValueDefinition)
      : name = inputValueDefinition.name,
        type = inputValueDefinition.type,
        super(
          sourceLocation: inputValueDefinition.sourceLocation,
          comments: inputValueDefinition.comments,
          ignoredChars: inputValueDefinition.ignoredChars,
          additionalData: inputValueDefinition.additionalData,
          directives: inputValueDefinition.directives,
        );

  InputValueDefinition build() => InputValueDefinition._(
        name: name,
        type: type,
        defaultValue: defaultValue,
        directives: directives,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
