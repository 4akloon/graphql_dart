import '../ast/definition.dart';
import '../ast/type_system_definition.dart';
import '../ast/type_system_extension.dart';

/// Tells whether a definition prints without the `{ ... }` body its grammar
/// allows, so that a `{` right after it would be read as that body.
final class BodyAbsorbingDefinition {
  /// Creates the check; it keeps no state.
  const BodyAbsorbingDefinition();

  /// Whether text that starts with `{` after [definition] belongs to it.
  ///
  /// Only an object, interface, input or enum type, its extension, or a
  /// schema extension with no members prints so; a schema definition
  /// always has its body, and a scalar, a union and a directive have none.
  bool isFollowedByBody(Definition definition) => switch (definition) {
    ObjectTypeDefinition(:final fields) => fields.isEmpty,
    InterfaceTypeDefinition(:final fields) => fields.isEmpty,
    InputObjectTypeDefinition(:final fields) => fields.isEmpty,
    EnumTypeDefinition(:final values) => values.isEmpty,
    ObjectTypeExtension(:final fields) => fields.isEmpty,
    InterfaceTypeExtension(:final fields) => fields.isEmpty,
    InputObjectTypeExtension(:final fields) => fields.isEmpty,
    EnumTypeExtension(:final values) => values.isEmpty,
    SchemaExtension(:final operationTypes) => operationTypes.isEmpty,
    _ => false,
  };
}
