import '../language/ast/name.dart';
import '../language/ast/type_ref.dart';
import '../schema/model/input_value.dart';
import '../schema/model/schema_field.dart';
import '../schema/model/schema_type.dart';
import '../schema/schema.dart';

/// The meta-fields of spec §4.1 "Type Name Introspection" and §4.2 "Schema
/// Introspection": fields every selection may ask for although no type
/// declares them.
final class MetaFields {
  MetaFields._();

  /// `__typename: String!`, on every composite type.
  static final SchemaField typename = SchemaField(
    '__typename',
    const NonNullType(NamedType(Name('String'))),
    description: 'The name of the current Object type at runtime.',
  );

  /// `__schema: __Schema!`, on the query root type.
  static final SchemaField schema = SchemaField(
    '__schema',
    const NonNullType(NamedType(Name('__Schema'))),
    description: 'Access the current type schema of this server.',
  );

  /// `__type(name: String!): __Type`, on the query root type.
  static final SchemaField type = SchemaField(
    '__type',
    const NamedType(Name('__Type')),
    description: 'Request the type information of a single type.',
    arguments: [
      InputValue('name', const NonNullType(NamedType(Name('String')))),
    ],
  );

  /// The field named [name] of [parentType] in [schema], meta-fields
  /// included, as graphql-js's `GraphQLSchema.getField`; null when there
  /// is none.
  static SchemaField? fieldOf(
    Schema schema,
    SchemaType parentType,
    String name,
  ) => switch (name) {
    '__schema' when _isQueryRoot(schema, parentType) => MetaFields.schema,
    '__type' when _isQueryRoot(schema, parentType) => type,
    '__typename' when parentType.isCompositeType => typename,
    _ => switch (parentType) {
      ObjectType() => parentType.fieldNamed(name),
      InterfaceType() => parentType.fieldNamed(name),
      _ => null,
    },
  };

  static bool _isQueryRoot(Schema schema, SchemaType type) =>
      switch (schema.queryTypeName) {
        final name? => identical(schema.typeNamed(name), type),
        null => false,
      };
}
