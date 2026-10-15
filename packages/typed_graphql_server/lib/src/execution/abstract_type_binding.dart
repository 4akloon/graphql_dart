import '../builder/object_type_def.dart';

/// How the executor resolves the runtime object type of a value of an
/// interface or union.
final class AbstractTypeBinding {
  /// Creates the binding of the abstract type [name].
  AbstractTypeBinding(
    this.name,
    this.resolveType,
    List<ObjectTypeDef<Object?>> possibleTypes,
  ) : possibleTypes = List.unmodifiable(possibleTypes);

  /// The abstract type's name.
  final String name;

  /// The explicit type resolution, null for the default (the first possible
  /// type that accepts the value).
  final ObjectTypeDef<Object?> Function(Object? value)? resolveType;

  /// The object types that can be a value, in schema order.
  final List<ObjectTypeDef<Object?>> possibleTypes;
}
