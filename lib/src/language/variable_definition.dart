import 'package:graphql_dart/src/language/abstract_node.dart';
import 'package:graphql_dart/src/language/directives_container.dart';
import 'package:graphql_dart/src/language/named_node.dart';
import 'package:graphql_dart/src/language/node.dart';
import 'package:graphql_dart/src/language/type.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';

import '../util/consumer.dart';
import '../util/traverser_context.dart';
import 'directive.dart';
import 'node_builder.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';
import 'value.dart';

class VariableDefinition extends AbstractNode<VariableDefinition>
    with DirectivesContainer<VariableDefinition>
    implements NamedNode<VariableDefinition> {
  static const String childType = 'type';
  static const String childDefaultValue = 'defaultValue';
  static const String childDirectives = 'directives';

  @override
  final String name;
  final GType type;
  final Value? defaultValue;
  @override
  final List<Directive> directives;

  VariableDefinition._({
    required this.name,
    required this.type,
    this.defaultValue,
    List<Directive> directives = const [],
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  }) : directives = List.unmodifiable(directives);

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
  VariableDefinition withNewChildren(NodeChildrenContainer newChildren) {
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
    } else if (node is VariableDefinition) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  VariableDefinition deepCopy() => VariableDefinition._(
        name: name,
        type: deepCopyFromNode(type)!,
        defaultValue: deepCopyFromNode(defaultValue),
        directives: deepCopyFromNodes<Directive>(directives) ?? [],
        sourceLocation: sourceLocation,
        comments: comments,
        additionalData: additionalData,
        ignoredChars: ignoredChars,
      );

  @override
  String toString() =>
      'VariableDefinition(name: $name, type: $type, defaultValue: $defaultValue, directives: $directives)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitVariableDefinition(this, context);
  }

  static VariableDefinitionBuilder builder({
    required String name,
    required GType type,
    Value? defaultValue,
  }) =>
      VariableDefinitionBuilder._(name, type, defaultValue);

  VariableDefinition transform(
      Consumer<VariableDefinitionBuilder> buildConsumer) {
    final builder = VariableDefinitionBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

class VariableDefinitionBuilder extends NodeBuilder {
  String name;
  GType type;
  Value? defaultValue;
  List<Directive> directives;

  VariableDefinitionBuilder._(
    this.name,
    this.type,
    this.defaultValue,
  ) : directives = [];

  VariableDefinitionBuilder._from(VariableDefinition variableDefinition)
      : name = variableDefinition.name,
        type = variableDefinition.type,
        defaultValue = variableDefinition.defaultValue,
        directives = variableDefinition.directives,
        super(
          sourceLocation: variableDefinition.sourceLocation,
          comments: variableDefinition.comments,
          ignoredChars: variableDefinition.ignoredChars,
          additionalData: variableDefinition.additionalData,
        );

  VariableDefinition build() => VariableDefinition._(
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
