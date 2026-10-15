/// What a planned data class is the shape of.
enum DataClassRole {
  /// The `data` of an operation.
  operationData,

  /// A fragment definition.
  fragment,

  /// The selection of a composite field.
  nested,

  /// The class of one concrete type of a polymorphic selection.
  variant,

  /// The class of every other type of a polymorphic selection.
  unknownVariant,
}
