import 'package:typed_graphql/typed_graphql.dart';

import 'directive_nodes.dart';
import 'enum_type_def.dart';
import 'field_assembler.dart';
import 'field_def.dart';
import 'field_inheritance.dart';
import 'input_object_def.dart';
import 'input_value_assembler.dart';
import 'interface_type_def.dart';
import 'named_type_def.dart';
import 'object_type_def.dart';
import 'scalar_type_def.dart';
import 'union_type_def.dart';

/// Turns a definition made through the builder into a core [SchemaType].
final class TypeAssembler {
  /// Creates the assembler; it writes arguments through [_inputs].
  TypeAssembler(this._inputs) : _fields = FieldAssembler(_inputs);

  final InputValueAssembler _inputs;
  final FieldAssembler _fields;

  static const DirectiveNodes _nodes = DirectiveNodes();

  /// The schema type for [definition].
  SchemaType assemble(NamedTypeDef definition) => switch (definition) {
    ScalarTypeDef<Object>() => _scalar(definition),
    EnumTypeDef<Enum>() => _enum(definition),
    ObjectTypeDef<Object?>() => _object(definition),
    InterfaceTypeDef<Object?>() => _interface(definition),
    UnionTypeDef<Object?>() => _union(definition),
    InputObjectDef<Object>() => _inputObject(definition),
    _ => throw StateError(
      'Unknown definition kind ${definition.runtimeType} for '
      '"${definition.name}".',
    ),
  };

  SchemaType _scalar(ScalarTypeDef<Object> definition) => ScalarType(
    definition.name,
    description: definition.description,
    appliedDirectives: [
      if (definition.specifiedByUrl case final url?) _nodes.specifiedBy(url),
    ],
  );

  SchemaType _enum(EnumTypeDef<Enum> definition) => EnumType(
    definition.name,
    description: definition.description,
    values: [
      for (final value in definition.values)
        SchemaEnumValue(
          value.name,
          description: value.description,
          appliedDirectives: _nodes.withDeprecation(
            const [],
            value.deprecationReason,
          ),
        ),
    ],
  );

  SchemaType _object(ObjectTypeDef<Object?> definition) => ObjectType(
    definition.name,
    description: definition.description,
    interfaces: _references(definition.interfaces),
    appliedDirectives: definition.options.directives,
    fields: _fieldsOf(
      definition.name,
      definition.fields,
      definition.interfaces,
    ),
  );

  SchemaType _interface(InterfaceTypeDef<Object?> definition) => InterfaceType(
    definition.name,
    description: definition.description,
    interfaces: _references(definition.interfaces),
    fields: _fieldsOf(
      definition.name,
      definition.fields,
      definition.interfaces,
    ),
  );

  SchemaType _union(UnionTypeDef<Object?> definition) => UnionType(
    definition.name,
    description: definition.description,
    memberTypes: _references(definition.members),
  );

  SchemaType _inputObject(InputObjectDef<Object> definition) => InputObjectType(
    definition.name,
    description: definition.description,
    appliedDirectives: [if (definition.isOneOf) _nodes.oneOf()],
    fields: [
      for (final field in definition.fields)
        _inputs.assemble(field, '${definition.name}.${field.name}'),
    ],
  );

  List<NamedTypeReference> _references(List<NamedTypeDef> definitions) => [
    for (final definition in definitions) NamedTypeReference(definition.name),
  ];

  // Own fields first, then those inherited from the listed interfaces.
  List<SchemaField> _fieldsOf(
    String typeName,
    List<FieldDef<Object?, Object?>> own,
    List<InterfaceTypeDef<Object?>> interfaces,
  ) => [
    for (final field in FieldInheritance().collect(own, interfaces))
      _fields.assemble(field, typeName),
  ];
}
