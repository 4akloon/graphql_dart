import '../builder/object_type_def.dart';

/// How the executor resolves the runtime object type of a value of an
/// interface or union.
final class AbstractTypeBinding {
  /// Creates the binding of the abstract type [name].
  AbstractTypeBinding(
    this.name,
    this.resolveType,
    List<ObjectTypeDef<Object?>> possibleTypes,
  ) : possibleTypes = List.unmodifiable(possibleTypes),
      _possibleSet = Set.identity()..addAll(possibleTypes);

  /// The abstract type's name.
  final String name;

  final Set<ObjectTypeDef<Object?>> _possibleSet;

  /// The explicit type resolution, null for the default (the first possible
  /// type that accepts the value).
  final ObjectTypeDef<Object?> Function(Object? value)? resolveType;

  /// The object types that can be a value, in schema order.
  final List<ObjectTypeDef<Object?>> possibleTypes;

  /// Whether [type] is one of the [possibleTypes].
  bool isPossible(ObjectTypeDef<Object?> type) => _possibleSet.contains(type);
}
