import 'package:graphql_dart/src/language/directives_container.dart';
import 'package:graphql_dart/src/language/named_node.dart';
import 'package:graphql_dart/src/language/sdl_named_definition.dart';

abstract interface class TypeDefinition<T extends TypeDefinition<dynamic>>
    with DirectivesContainer<T>
    implements SDLNamedDefinition<T>, NamedNode<T> {}
