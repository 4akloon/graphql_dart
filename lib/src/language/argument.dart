import 'package:graphql_dart/src/language/ignored_chars.dart';
import 'package:graphql_dart/src/language/node.dart';
import 'package:graphql_dart/src/language/node_children_container.dart';
import 'package:graphql_dart/src/language/source_location.dart';
import 'package:graphql_dart/src/util/traversal_control.dart';
import 'package:graphql_dart/src/util/traverser_context.dart';

import '../util/consumer.dart';
import 'abstract_node.dart';
import 'comment.dart';
import 'named_node.dart';
import 'node_builder.dart';
import 'node_visitor.dart';
import 'value.dart';

class Argument extends AbstractNode<Argument> implements NamedNode<Argument> {
  static const String childValue = 'value';

  @override
  final String? name;
  final Value? value;

  Argument({
    this.name,
    required this.value,
    super.sourceLocation,
    super.comments = const [],
    super.additionalData = const {},
    IgnoredChars? ignoredChars,
  }) : super(ignoredChars: ignoredChars ?? IgnoredChars.empty());

  static ArgumentBuilder newArgument({
    String? name,
    Value? value,
  }) =>
      ArgumentBuilder._(name, value);

  @override
  List<Node> get children => value == null ? [] : [value!];

  @override
  NodeChildrenContainer get namedChildren =>
      NodeChildrenContainer.builder().child(childValue, value).build();

  @override
  Argument withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) => builder.value(newChildren.getChild(childValue)),
    );
  }

  @override
  bool isEqualTo(Node? node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node?.runtimeType) {
      return false;
    } else if (node is Argument) {
      return name == node.name;
    } else {
      return false;
    }
  }

  @override
  Argument deepCopy() {
    return Argument(
      name: name,
      value: deepCopyFromNode(value),
      sourceLocation: sourceLocation,
      comments: comments,
      ignoredChars: ignoredChars,
      additionalData: additionalData,
    );
  }

  @override
  String toString() => 'Argument(name: $name, value: $value)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitArgument(this, context);
  }

  Argument transform(Consumer<ArgumentBuilder> builderConsumer) {
    final builder = ArgumentBuilder._from(this);
    builderConsumer(builder);
    return builder.build();
  }
}

final class ArgumentBuilder implements NodeBuilder {
  SourceLocation? _sourceLocation;
  List<Comment> _comments = [];
  String? _name;
  Value? _value;
  IgnoredChars _ignoredChars = IgnoredChars.empty();
  Map<String, String> _additionalData = {};

  ArgumentBuilder._(String? name, Value? value)
      : _name = name,
        _value = value;

  ArgumentBuilder._from(Argument argument)
      : _sourceLocation = argument.sourceLocation,
        _comments = List.unmodifiable(argument.comments),
        _name = argument.name,
        _ignoredChars = argument.ignoredChars,
        _additionalData = argument.additionalData;

  @override
  ArgumentBuilder sourceLocation(SourceLocation? sourceLocation) {
    _sourceLocation = sourceLocation;
    return this;
  }

  ArgumentBuilder name(String? name) {
    _name = name;
    return this;
  }

  ArgumentBuilder value(Value? value) {
    _value = value;
    return this;
  }

  @override
  ArgumentBuilder comments(List<Comment> comments) {
    _comments = comments;
    return this;
  }

  @override
  ArgumentBuilder ignoredChars(IgnoredChars ignoredChars) {
    _ignoredChars = ignoredChars;
    return this;
  }

  @override
  NodeBuilder additionalData(Map<String, String> additionalData) {
    _additionalData = additionalData;
    return this;
  }

  @override
  NodeBuilder additionalDataEntry(String key, String value) {
    _additionalData[key] = value;
    return this;
  }

  Argument build() => Argument(
        name: _name,
        value: _value,
        sourceLocation: _sourceLocation,
        comments: _comments,
        ignoredChars: _ignoredChars,
        additionalData: _additionalData,
      );
}
