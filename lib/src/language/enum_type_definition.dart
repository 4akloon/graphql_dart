import 'package:graphql_dart/src/language/abstract_described_node.dart';
import 'package:graphql_dart/src/language/directives_container.dart';
import 'package:graphql_dart/src/language/named_node.dart';
import 'package:graphql_dart/src/language/node_visitor.dart';
import 'package:graphql_dart/src/language/type_definition.dart';
import 'package:graphql_dart/src/util/consumer.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';
import 'package:graphql_dart/src/util/traverser_context.dart';

import 'description.dart';
import 'directive.dart';
import 'enum_value_definition.dart';
import 'node.dart';
import 'node_children_container.dart';
import 'node_directives_builder.dart';

class EnumTypeDefinition extends AbstractDescribedNode<EnumTypeDefinition>
    with DirectivesContainer<EnumTypeDefinition>
    implements
        TypeDefinition<EnumTypeDefinition>,
        NamedNode<EnumTypeDefinition> {
  static const String childEnumValueDefinitions = 'enumValueDefinitions';
  static const String childDirectives = 'directives';

  @override
  final String name;
  final List<EnumValueDefinition> enumValueDefinitions;
  @override
  final List<Directive> directives;

  EnumTypeDefinition._({
    required this.name,
    List<EnumValueDefinition> enumValueDefinitions = const [],
    List<Directive> directives = const [],
    super.description,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    super.ignoredChars,
  })  : enumValueDefinitions = List.unmodifiable(enumValueDefinitions),
        directives = List.unmodifiable(directives);

  @override
  List<Node> get children => List.unmodifiable([
        ...enumValueDefinitions,
        ...directives,
      ]);

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .children(childEnumValueDefinitions, enumValueDefinitions)
      .children(childDirectives, directives)
      .build();

  @override
  EnumTypeDefinition withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) => builder
        ..enumValueDefinitions =
            newChildren.getChildrenValue(childEnumValueDefinitions)
        ..directives = newChildren.getChildrenValue(childDirectives),
    );
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else if (node is EnumTypeDefinition) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  EnumTypeDefinition deepCopy() => EnumTypeDefinition._(
        name: name,
        enumValueDefinitions: deepCopyFromNodes(enumValueDefinitions) ?? [],
        directives: deepCopyFromNodes(directives) ?? [],
        description: description,
        sourceLocation: sourceLocation,
        comments: comments,
        additionalData: additionalData,
        ignoredChars: ignoredChars,
      );

  @override
  String toString() =>
      'EnumTypeDefinition(name: $name, enumValueDefinitions: $enumValueDefinitions, directives: $directives)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitEnumTypeDefinition(this, context);
  }

  static EnumTypeDefinitionBuilder builder(String name) =>
      EnumTypeDefinitionBuilder._(name);

  EnumTypeDefinition transform(
      Consumer<EnumTypeDefinitionBuilder> buildConsumer) {
    final builder = EnumTypeDefinitionBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

class EnumTypeDefinitionBuilder extends NodeDirectivesBuilder {
  final String name;
  Description? description;
  List<EnumValueDefinition> enumValueDefinitions;

  EnumTypeDefinitionBuilder._(this.name) : enumValueDefinitions = [];

  EnumTypeDefinitionBuilder._from(EnumTypeDefinition existing)
      : name = existing.name,
        enumValueDefinitions = existing.enumValueDefinitions,
        description = existing.description,
        super(
          directives: existing.directives,
          sourceLocation: existing.sourceLocation,
          comments: existing.comments,
          ignoredChars: existing.ignoredChars,
          additionalData: existing.additionalData,
        );

  EnumTypeDefinition build() {
    return EnumTypeDefinition._(
      name: name,
      enumValueDefinitions: enumValueDefinitions,
      directives: directives,
      description: description,
      sourceLocation: sourceLocation,
      comments: comments,
      ignoredChars: ignoredChars,
      additionalData: additionalData,
    );
  }
}
