import '../builder/field_def.dart';
import '../builder/input_object_def.dart';
import '../builder/named_type_def.dart';
import '../builder/object_type_def.dart';
import 'abstract_type_binding.dart';

/// What the executor needs at run time, by type name: the Dart-side
/// counterpart of the core schema.
final class SchemaBindings {
  /// Creates the tables; each is copied unmodifiable.
  SchemaBindings({
    required Map<String, ObjectTypeDef<Object?>> objects,
    required Map<String, Map<String, FieldDef<Object?, Object?>>> fields,
    required Map<String, AbstractTypeBinding> abstractTypes,
    required Map<String, NamedTypeDef> leaves,
    required Map<String, InputObjectDef<Object>> inputObjects,
  }) : objects = Map.unmodifiable(objects),
       fields = Map.unmodifiable(fields),
       abstractTypes = Map.unmodifiable(abstractTypes),
       leaves = Map.unmodifiable(leaves),
       inputObjects = Map.unmodifiable(inputObjects);

  /// The same tables with [fields] in place of the field tables.
  SchemaBindings withFields(
    Map<String, Map<String, FieldDef<Object?, Object?>>> fields,
  ) => SchemaBindings(
    objects: objects,
    fields: fields,
    abstractTypes: abstractTypes,
    leaves: leaves,
    inputObjects: inputObjects,
  );

  /// The same tables with the introspection [fields] (every object's, the
  /// introspection types' included) and [introspectionLeaves] added to the
  /// scalar and enum definitions.
  SchemaBindings withIntrospection(
    Map<String, Map<String, FieldDef<Object?, Object?>>> fields,
    Map<String, NamedTypeDef> introspectionLeaves,
  ) => SchemaBindings(
    objects: objects,
    fields: fields,
    abstractTypes: abstractTypes,
    leaves: {...leaves, ...introspectionLeaves},
    inputObjects: inputObjects,
  );

  /// The object types.
  final Map<String, ObjectTypeDef<Object?>> objects;

  /// The fields of each object type by field name, inherited ones included.
  final Map<String, Map<String, FieldDef<Object?, Object?>>> fields;

  /// The interfaces and unions.
  final Map<String, AbstractTypeBinding> abstractTypes;

  /// The scalar and enum definitions (`ScalarTypeDef`, `EnumTypeDef`).
  final Map<String, NamedTypeDef> leaves;

  /// The input objects.
  final Map<String, InputObjectDef<Object>> inputObjects;
}
