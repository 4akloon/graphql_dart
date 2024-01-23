import 'directive.dart';
import 'node_builder.dart';

abstract class NodeDirectivesBuilder extends NodeBuilder {
  List<Directive> directives;

  NodeDirectivesBuilder({
    this.directives = const [],
    super.sourceLocation,
    super.comments = const [],
    super.ignoredChars,
    super.additionalData = const {},
  });

  set directive(Directive directive) {
    directives = List.unmodifiable([...directives, directive]);
  }
}
