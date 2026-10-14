import '../../language/ast/type_system_definition.dart';
import '../model/schema_type.dart';
import 'element_reader.dart';

/// Reads a type definition into a [SchemaType] of the same kind, with its
/// members and span.
final class const TypeReader(
  /// Reads the members and gives the spans.
  final ElementReader elements,
) {
  /// Creates a reader.
  this;

  /// The schema type [node] defines.
  SchemaType type(TypeDefinition node) => switch (node) {
    ScalarTypeDefinition() => ScalarType(
      node.name.value,
      description: node.description?.value,
      appliedDirectives: elements.appliedAll(node.directives),
      span: elements.spans.of(node),
    ),
    ObjectTypeDefinition() => _object(node),
    InterfaceTypeDefinition() => _interface(node),
    UnionTypeDefinition() => UnionType(
      node.name.value,
      description: node.description?.value,
      appliedDirectives: elements.appliedAll(node.directives),
      memberTypes: elements.references(node.types),
      span: elements.spans.of(node),
    ),
    EnumTypeDefinition() => _enum(node),
    InputObjectTypeDefinition() => _inputObject(node),
  };

  ObjectType _object(ObjectTypeDefinition node) => ObjectType(
    node.name.value,
    description: node.description?.value,
    interfaces: elements.references(node.interfaces),
    appliedDirectives: elements.appliedAll(node.directives),
    fields: node.fields.map(elements.field).toList(),
    span: elements.spans.of(node),
  );

  InterfaceType _interface(InterfaceTypeDefinition node) => InterfaceType(
    node.name.value,
    description: node.description?.value,
    interfaces: elements.references(node.interfaces),
    appliedDirectives: elements.appliedAll(node.directives),
    fields: node.fields.map(elements.field).toList(),
    span: elements.spans.of(node),
  );

  EnumType _enum(EnumTypeDefinition node) => EnumType(
    node.name.value,
    description: node.description?.value,
    appliedDirectives: elements.appliedAll(node.directives),
    values: node.values.map(elements.enumValue).toList(),
    span: elements.spans.of(node),
  );

  InputObjectType _inputObject(InputObjectTypeDefinition node) =>
      InputObjectType(
        node.name.value,
        description: node.description?.value,
        appliedDirectives: elements.appliedAll(node.directives),
        fields: node.fields.map(elements.inputValue).toList(),
        span: elements.spans.of(node),
      );
}
