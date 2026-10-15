import 'package:typed_graphql/typed_graphql.dart';

/// The two meta fields that open introspection, `__schema` and `__type`
/// (September2025 4.2). Only the query root type has them, as graphql-js's
/// `getFieldDef` finds them; the schema does not declare them.
final class const EntryFields() {
  /// Creates the reader.
  this;

  /// `__schema: __Schema!`.
  static final SchemaField schemaField = SchemaField(
    '__schema',
    const NonNullType(NamedType(Name('__Schema'))),
    description: 'Access the current type schema of this server.',
  );

  /// `__type(name: String!): __Type`.
  static final SchemaField typeField = SchemaField(
    '__type',
    const NamedType(Name('__Type')),
    description: 'Request the type information of a single type.',
    arguments: [
      InputValue('name', const NonNullType(NamedType(Name('String')))),
    ],
  );

  /// Whether [fieldName] opens introspection.
  bool isEntry(String fieldName) =>
      fieldName == '__schema' || fieldName == '__type';

  /// The entry field named [fieldName] of [parentType], null when the name
  /// is another one or [parentType] is not the query root.
  SchemaField? of(Schema schema, ObjectType parentType, String fieldName) {
    if (parentType.name != schema.queryTypeName) {
      return null;
    }
    return switch (fieldName) {
      '__schema' => schemaField,
      '__type' => typeField,
      _ => null,
    };
  }
}
