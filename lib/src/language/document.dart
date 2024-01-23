import 'abstract_node.dart';
import 'definition.dart';

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
}
