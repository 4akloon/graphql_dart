import 'package:typed_graphql/typed_graphql.dart';

/// The value of a `__Type` object: a type as a schema writes it, a name or a
/// list or non-null wrapper around another type (September2025 4.2.1).
///
/// A wrapper is not a schema type, which is why introspection needs its own
/// value instead of the core's [SchemaType].
final class IntrospectedType(
  /// The type reference this value stands for.
  final TypeRef reference,
) {
  /// Wraps [reference].
  this;

  /// The value for the named type [name].
  factory IntrospectedType.named(String name) =>
      IntrospectedType(NamedType(Name(name)));
}
