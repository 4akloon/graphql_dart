import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// Finds which operation a request selects, as the executor will.
@internal
final class OperationLookup {
  /// Creates the lookup.
  const OperationLookup();

  /// The operation of [document] named [operationName] (the only operation
  /// when null), or null when there is none to select; the executor then
  /// reports `GQL320`-`GQL322` (September2025 6.1.2).
  OperationDefinition? operationOf(Document document, String? operationName) {
    final operations = document.definitions.whereType<OperationDefinition>();
    if (operationName == null) {
      return operations.length == 1 ? operations.first : null;
    }
    for (final operation in operations) {
      if (operation.name?.value == operationName) {
        return operation;
      }
    }
    return null;
  }
}
