import 'package:typed_graphql/typed_graphql.dart';

/// Every field node of one response name at one level of a selection.
final class FieldGroup(
  /// The key in the response: the alias, or the field name.
  final String responseName,

  /// The name of the field in the schema.
  final String fieldName,

  /// Every node with this response name, in document order.
  List<Field> nodes, {

  /// The schema field, looked up on the parent type.
  required final SchemaField definition,

  /// Whether every node is under a variable condition, its own or an
  /// enclosing inline fragment's.
  final bool isConditional = false,
}) {
  /// Creates a group.
  this;

  /// The nodes, in document order.
  final List<Field> nodes = List.unmodifiable(nodes);
}
