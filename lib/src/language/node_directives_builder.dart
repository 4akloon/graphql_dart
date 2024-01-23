import 'directive.dart';
import 'node_builder.dart';

abstract interface class NodeDirectivesBuilder implements NodeBuilder {
  NodeDirectivesBuilder directives(List<Directive> directives);

  NodeDirectivesBuilder directive(Directive directive);
}
