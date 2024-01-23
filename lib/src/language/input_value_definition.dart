import 'package:graphql_dart/src/language/directive.dart';
import 'package:graphql_dart/src/language/node.dart';
import 'package:graphql_dart/src/language/node_children_container.dart';
import 'package:graphql_dart/src/language/node_visitor.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';
import 'package:graphql_dart/src/util/traverser_context.dart';

import '../util/consumer.dart';
import 'abstract_described_node.dart';
import 'comment.dart';
import 'directives_container.dart';
import 'ignored_chars.dart';
import 'named_node.dart';
import 'node_directives_builder.dart';
import 'source_location.dart';
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
          .type(newChildren.getChild(childType) as GType)
          .defaultValue(newChildren.getChild(childDefaultValue))
          .directives(newChildren.getChildrenValue(childDirectives)),
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

final class InputValueDefinitionBuilder implements NodeDirectivesBuilder {
  SourceLocation? _sourceLocation;
  List<Comment> _comments = [];
  String _name;
  GType _type;
  Value? _defaultValue;
  List<Directive> _directives = [];
  IgnoredChars _ignoredChars = IgnoredChars.empty();
  Map<String, String> _additionalData = {};

  InputValueDefinitionBuilder._(String name, GType type)
      : _name = name,
        _type = type;

  InputValueDefinitionBuilder._from(InputValueDefinition inputValueDefinition)
      : _sourceLocation = inputValueDefinition.sourceLocation,
        _comments = List.unmodifiable(inputValueDefinition.comments),
        _name = inputValueDefinition.name,
        _type = inputValueDefinition.type,
        _defaultValue = inputValueDefinition.defaultValue,
        _directives = List.unmodifiable(inputValueDefinition.directives),
        _ignoredChars = inputValueDefinition.ignoredChars,
        _additionalData = {...inputValueDefinition.additionalData};

  @override
  InputValueDefinitionBuilder sourceLocation(SourceLocation? sourceLocation) {
    _sourceLocation = sourceLocation;
    return this;
  }

  @override
  InputValueDefinitionBuilder comments(List<Comment> comments) {
    _comments = comments;
    return this;
  }

  InputValueDefinitionBuilder name(String name) {
    _name = name;
    return this;
  }

  InputValueDefinitionBuilder type(GType type) {
    _type = type;
    return this;
  }

  InputValueDefinitionBuilder defaultValue(Value? defaultValue) {
    _defaultValue = defaultValue;
    return this;
  }

  @override
  InputValueDefinitionBuilder directives(List<Directive> directives) {
    _directives = directives;
    return this;
  }

  @override
  InputValueDefinitionBuilder directive(Directive directive) {
    _directives = List.unmodifiable([..._directives, directive]);
    return this;
  }

  @override
  InputValueDefinitionBuilder ignoredChars(IgnoredChars ignoredChars) {
    _ignoredChars = ignoredChars;
    return this;
  }

  @override
  InputValueDefinitionBuilder additionalData(
      Map<String, String> additionalData) {
    _additionalData = additionalData;
    return this;
  }

  @override
  InputValueDefinitionBuilder additionalDataEntry(String key, String value) {
    _additionalData[key] = value;
    return this;
  }

  InputValueDefinition build() => InputValueDefinition._(
        name: _name,
        type: _type,
        defaultValue: _defaultValue,
        directives: _directives,
        sourceLocation: _sourceLocation,
        comments: _comments,
        ignoredChars: _ignoredChars,
        additionalData: _additionalData,
      );
}
