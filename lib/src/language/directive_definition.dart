import 'package:graphql_dart/src/language/named_node.dart';
import 'package:graphql_dart/src/language/sdl_named_definition.dart';

import 'abstract_described_node.dart';

class DirectiveDefinition extends AbstractDescribedNode<DirectiveDefinition>
    implements
        SDLNamedDefinition<DirectiveDefinition>,
        NamedNode<DirectiveDefinition> {
  final String name;
  final bool repeatable;
}
