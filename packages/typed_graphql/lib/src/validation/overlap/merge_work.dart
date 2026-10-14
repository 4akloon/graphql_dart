import 'merge_item.dart';

/// Fields with one response name at one place, to check together, and
/// which of the two checks of spec §5.3.2 apply to them.
final class const MergeWork(
  /// The fields, in graphql-js's collection order.
  final List<MergeItem> items, {

  /// Whether the fields must have the same response shape
  /// (`SameResponseShape`).
  final bool checksShape = true,

  /// Whether fields with a common parent type must select the same field
  /// with the same arguments (`FieldsInSetCanMerge`).
  final bool checksNames = true,
}) {
  /// Creates the work.
  this;
}
