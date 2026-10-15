import '../../language/ast/selection.dart';
import '../../schema/model/schema_field.dart';
import 'field_origin.dart';
import 'fragment_trail.dart';

/// A field in a merged selection: the node, where it is written, its
/// definition in the schema and the item it is selected under.
///
/// The same node is one item per place it is reached from, so a fragment
/// spread under two fields gives two items with different parents.
final class MergeItem(
  /// The field node.
  final Field node,

  /// Where [node] is written.
  final FieldOrigin origin,

  /// The field of the parent type that [node] selects; null when the
  /// parent type is unknown or not an object or interface type, as
  /// graphql-js's `getFields` lookup (no meta-fields).
  final SchemaField? definition,

  /// The item whose selection set holds [node]; null at the top of an
  /// operation or fragment.
  final MergeItem? parent,

  /// The fragments spread between the parent's selection set and [node].
  final FragmentTrail trail,
) {
  /// Creates an item.
  this;

  /// The key of the field in a response: its alias, else its name.
  String get responseName => node.alias?.value ?? node.name.value;
}
