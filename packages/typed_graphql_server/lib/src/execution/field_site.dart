import 'package:typed_graphql/typed_graphql.dart';

/// Where a middleware is composed: an object type and one of its fields.
///
/// An inherited interface field is composed once per implementing object
/// type, so [parentType] is always the object type.
///
/// {@category execution}
final class FieldSite {
  /// Names the [field] of [parentType].
  const FieldSite(this.parentType, this.field);

  /// The object type that has the field.
  final ObjectType parentType;

  /// The field in the built schema.
  final SchemaField field;
}
