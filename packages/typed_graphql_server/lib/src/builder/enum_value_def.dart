/// One value of an `EnumTypeDef`: the Dart value and what the schema says
/// about it.
///
/// {@category builder}
final class const EnumValueDef<E extends Enum>(
  /// The Dart value.
  final E value,

  /// The value's name in the schema.
  final String name, {

  /// The value's description, null when it has none.
  final String? description,

  /// Why the value is deprecated, null when it is not.
  final String? deprecationReason,
}) {
  /// Describes [value], named [name] in the schema.
  this;
}
