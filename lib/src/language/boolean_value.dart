import '../util/consumer.dart';
import '../util/node_util.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_node.dart';
import 'comment.dart';
import 'ignored_chars.dart';
import 'node.dart';
import 'node_builder.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';
import 'scalar_value.dart';
import 'source_location.dart';

class BooleanValue extends AbstractNode<BooleanValue>
    implements ScalarValue<BooleanValue> {
  final bool value;

  BooleanValue({
    required this.value,
    super.sourceLocation,
    super.comments = const [],
    IgnoredChars? ignoredChars,
    super.additionalData = const {},
  }) : super(ignoredChars: ignoredChars ?? IgnoredChars.empty());

  @override
  List<Node> get children => const [];

  @override
  NodeChildrenContainer get namedChildren =>
      NodeChildrenContainer.builder().build();

  @override
  BooleanValue withNewChildren(NodeChildrenContainer newChildren) {
    NodeUtil.assertNewChildrenAreEmpty(newChildren);
    return this;
  }

  @override
  bool isEqualTo(Node node) {
    if (this == node) {
      return true;
    } else if (runtimeType != node.runtimeType) {
      return false;
    } else {
      return false;
    }
  }

  @override
  BooleanValue deepCopy() => BooleanValue(
        value: value,
        ignoredChars: ignoredChars,
        comments: comments,
        additionalData: additionalData,
        sourceLocation: sourceLocation,
      );

  @override
  String toString() => 'BooleanValue(value: $value)';

  factory BooleanValue.of(bool value) => builder(value).build();

  static BooleanValueBuilder builder(bool value) =>
      BooleanValueBuilder._(value);

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitBooleanValue(this, context);
  }

  BooleanValue transform(Consumer<BooleanValueBuilder> buildConsumer) {
    final builder = BooleanValueBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class BooleanValueBuilder implements NodeBuilder {
  SourceLocation? _sourceLocation;
  bool _value;
  List<Comment> _comments = [];
  IgnoredChars _ignoredChars = IgnoredChars.empty();
  Map<String, String> _additionalData = {};

  BooleanValueBuilder._(this._value);

  BooleanValueBuilder._from(BooleanValue existing)
      : _value = existing.value,
        _sourceLocation = existing.sourceLocation,
        _comments = List.unmodifiable(existing.comments),
        _ignoredChars = existing.ignoredChars,
        _additionalData = {...existing.additionalData};

  @override
  BooleanValueBuilder sourceLocation(SourceLocation? sourceLocation) {
    _sourceLocation = sourceLocation;
    return this;
  }

  BooleanValueBuilder value(bool value) {
    _value = value;
    return this;
  }

  @override
  BooleanValueBuilder comments(List<Comment> comments) {
    _comments = comments;
    return this;
  }

  @override
  BooleanValueBuilder ignoredChars(IgnoredChars ignoredChars) {
    _ignoredChars = ignoredChars;
    return this;
  }

  @override
  BooleanValueBuilder additionalData(Map<String, String> additionalData) {
    _additionalData = additionalData;
    return this;
  }

  @override
  BooleanValueBuilder additionalDataEntry(String key, String value) {
    _additionalData[key] = value;
    return this;
  }

  BooleanValue build() {
    return BooleanValue(
      value: _value,
      sourceLocation: _sourceLocation,
      comments: _comments,
      ignoredChars: _ignoredChars,
      additionalData: _additionalData,
    );
  }
}
