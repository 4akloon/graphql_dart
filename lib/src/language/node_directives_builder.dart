import 'directive.dart';
import 'node_builder.dart';

abstract class NodeDirectivesBuilder extends NodeBuilder {
  List<Directive> directives;

  NodeDirectivesBuilder({
    List<Directive> directives = const [],
    super.sourceLocation,
    super.comments = const [],
    super.ignoredChars,
    super.additionalData = const {},
  }) : directives = List.unmodifiable(directives);

  set directive(Directive directive) {
    directives = List.unmodifiable([...directives, directive]);
  }
}
