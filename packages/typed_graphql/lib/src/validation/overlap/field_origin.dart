import '../../schema/model/schema_type.dart';

/// Where a field is written: the type its selection set selects from, as
/// the walk's type information saw it.
final class const FieldOrigin(
  /// The type the field is selected on; null when it is unknown.
  final SchemaType? parentType,
) {
  /// Creates an origin.
  this;
}
