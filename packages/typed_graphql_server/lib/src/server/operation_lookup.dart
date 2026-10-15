import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../plan/operation_selection.dart';
import '../plan/operation_selection_result.dart';

/// Finds which operation a request selects with the executor's own
/// selection, so the method check and the cost limit judge the operation
/// that runs, even when caller-supplied rules let two operations share a
/// name (the executor takes the last).
@internal
final class OperationLookup {
  /// Creates the lookup over [selection].
  const OperationLookup(this.selection);

  /// The executor's selection (September2025 6.1 `GetOperation`).
  final OperationSelection selection;

  /// The operation of [document] named [operationName] (the only operation
  /// when null), or null when there is none to select; the executor then
  /// reports why (`GQL320`-`GQL323`).
  OperationDefinition? operationOf(Document document, String? operationName) =>
      switch (selection.select(document, operationName)) {
        OperationSelected(:final operation) => operation,
        OperationRejected() => null,
      };
}
