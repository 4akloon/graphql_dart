import '../execution/abstract_type_binding.dart';
import '../execution/schema_bindings.dart';
import 'enum_type_def.dart';
import 'field_def.dart';
import 'field_inheritance.dart';
import 'input_object_def.dart';
import 'interface_type_def.dart';
import 'named_type_def.dart';
import 'object_type_def.dart';
import 'possible_types.dart';
import 'scalar_type_def.dart';
import 'union_type_def.dart';

/// Builds the [SchemaBindings] of a set of definitions.
final class SchemaBindingsAssembler {
  /// Creates the assembler.
  SchemaBindingsAssembler();

  final Map<String, ObjectTypeDef<Object?>> _objects = {};
  final Map<String, Map<String, FieldDef<Object?, Object?>>> _fields = {};
  final Map<String, AbstractTypeBinding> _abstractTypes = {};
  final Map<String, NamedTypeDef> _leaves = {};
  final Map<String, InputObjectDef<Object>> _inputObjects = {};

  /// The tables for [definitions], with [possibleTypes] for the abstract
  /// ones. The first definition of a name wins, as in the schema.
  ///
  /// An assembler is used for one call.
  SchemaBindings assemble(
    List<NamedTypeDef> definitions,
    PossibleTypes possibleTypes,
  ) {
    for (final definition in definitions) {
      switch (definition) {
        case ObjectTypeDef<Object?>():
          _addObject(definition);
        case InterfaceTypeDef<Object?>(:final untypedResolveType) ||
            UnionTypeDef<Object?>(:final untypedResolveType):
          _abstractTypes.putIfAbsent(
            definition.name,
            () => AbstractTypeBinding(
              definition.name,
              untypedResolveType,
              possibleTypes.of(definition),
            ),
          );
        case ScalarTypeDef<Object>() || EnumTypeDef<Enum>():
          _leaves.putIfAbsent(definition.name, () => definition);
        case InputObjectDef<Object>():
          _inputObjects.putIfAbsent(definition.name, () => definition);
        default:
      }
    }
    return SchemaBindings(
      objects: _objects,
      fields: _fields,
      abstractTypes: _abstractTypes,
      leaves: _leaves,
      inputObjects: _inputObjects,
    );
  }

  void _addObject(ObjectTypeDef<Object?> definition) {
    _objects.putIfAbsent(definition.name, () => definition);
    _fields.putIfAbsent(definition.name, () {
      final collected = FieldInheritance().collect(
        definition.fields,
        definition.interfaces,
      );
      return {for (final field in collected) field.name: field};
    });
  }
}
