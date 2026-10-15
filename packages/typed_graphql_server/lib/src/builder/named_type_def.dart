/// A named GraphQL type declared through `ExecutableSchemaBuilder`.
///
/// Holds the name and description only; what a definition can do at run time
/// lives in the subclasses and in the schema binding tables.
///
/// {@category builder}
abstract base class const NamedTypeDef(
  /// The type's name.
  final String name, {

  /// The type's description, null when it has none.
  final String? description,
}) {
  /// Creates a definition named [name].
  this;
}
