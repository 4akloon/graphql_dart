import '../../language/ast/document.dart';
import '../../language/ast/executable_definition.dart';
import '../../language/ast/type_system_definition.dart';

/// The definitions of a document sorted by what the builder does with
/// them, each list in document order.
final class DocumentDefinitions {
  /// Sorts the definitions of [document].
  DocumentDefinitions.of(Document document) {
    for (final definition in document.definitions) {
      switch (definition) {
        case SchemaDefinition():
          schemas.add(definition);
        case TypeDefinition():
          types.add(definition);
        case DirectiveDefinition():
          directives.add(definition);
        case ExecutableDefinition():
          executables.add(definition);
      }
    }
  }

  /// The schema definitions; a valid document has at most one.
  final List<SchemaDefinition> schemas = [];

  /// The type definitions.
  final List<TypeDefinition> types = [];

  /// The directive definitions.
  final List<DirectiveDefinition> directives = [];

  /// What a schema cannot hold: operations and fragments.
  final List<ExecutableDefinition> executables = [];
}
