import 'package:collection/collection.dart';

import '../util/consumer.dart';
import '../util/traversal_control.dart';
import '../util/traverser_context.dart';
import 'abstract_node.dart';
import 'definition.dart';
import 'node.dart';
import 'node_builder.dart';
import 'node_children_container.dart';
import 'node_visitor.dart';
import 'operation_definition.dart';

class Document extends AbstractNode<Document> {
  static const String childDefinitions = 'definitions';

  final List<Definition> definitions;

  Document._({
    List<Definition> definitions = const [],
    super.sourceLocation,
    super.comments = const [],
    super.ignoredChars,
    super.additionalData = const {},
  }) : definitions = List.unmodifiable(definitions);

  List<T> getDefinitions<T extends Definition>() =>
      List.unmodifiable(definitions.whereType<T>());

  T? getFirstDefinition<T extends Definition>() =>
      definitions.whereType<T>().firstOrNull;

  OperationDefinition? getOperationDefinition(String name) => definitions
      .whereType<OperationDefinition>()
      .firstWhereOrNull((definition) => definition.name == name);

  @override
  List<Node> get children => List.unmodifiable(definitions);

  @override
  NodeChildrenContainer get namedChildren => NodeChildrenContainer.builder()
      .children(childDefinitions, definitions)
      .build();

  @override
  Document withNewChildren(NodeChildrenContainer newChildren) {
    return transform(
      (builder) =>
          builder..definitions = newChildren.getChildrenValue(childDefinitions),
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
  Document deepCopy() => Document._(
        definitions: deepCopyFromNodes(definitions) ?? [],
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );

  @override
  String toString() => 'Document(definitions: $definitions)';

  @override
  TraversalControl accept(TraverserContext<Node> context, NodeVisitor visitor) {
    return visitor.visitDocument(this, context);
  }

  static DocumentBuilder builder() => DocumentBuilder._([]);

  Document transform(Consumer<DocumentBuilder> buildConsumer) {
    final builder = DocumentBuilder._from(this);
    buildConsumer(builder);
    return builder.build();
  }
}

final class DocumentBuilder extends NodeBuilder {
  List<Definition> definitions;

  DocumentBuilder._(this.definitions);

  DocumentBuilder._from(Document document)
      : definitions = document.definitions,
        super(
          sourceLocation: document.sourceLocation,
          comments: document.comments,
          ignoredChars: document.ignoredChars,
          additionalData: document.additionalData,
        );

  set definition(Definition definition) =>
      definitions = [...definitions, definition];

  Document build() => Document._(
        definitions: definitions,
        sourceLocation: sourceLocation,
        comments: comments,
        ignoredChars: ignoredChars,
        additionalData: additionalData,
      );
}
