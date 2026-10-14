import 'child_reader.dart';
import 'node.dart';
import 'operation_type.dart';
import 'type_ref.dart';

/// A root operation type of a schema, `query: Query` (spec §3.3.1).
final class const OperationTypeDefinition(
  /// The operation the type serves.
  final OperationType operation,

  /// The root type.
  final NamedType type, {
  super.start,
  super.end,
}) extends Node {
  /// Creates a root operation type definition.
  this;

  @override
  List<Node> get children => [type];

  @override
  List<Object?> get scalars => [operation];

  @override
  OperationTypeDefinition rebuildFrom(ChildReader read) =>
      OperationTypeDefinition(
        operation,
        read.one(),
        start: start,
        end: end,
      );
}
