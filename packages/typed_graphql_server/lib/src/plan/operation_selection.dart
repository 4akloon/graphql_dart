import 'package:typed_graphql/typed_graphql.dart';

import 'operation_selection_result.dart';

/// September2025 section 6.1 `GetOperation`, worded as graphql-js 17's
/// `buildExecutionContext` words it, plus the check that the schema has a
/// root type for the operation (graphql-js checks it when it executes).
final class OperationSelection {
  /// Selects against [schema].
  const OperationSelection(this.schema);

  /// The schema whose root types are checked.
  final Schema schema;

  /// Chooses the operation of [document] named [operationName]; without a
  /// name the document must hold exactly one operation.
  OperationSelectionResult select(Document document, String? operationName) {
    OperationDefinition? chosen;
    for (final definition in document.definitions) {
      if (definition is! OperationDefinition) {
        continue;
      }
      if (operationName == null) {
        if (chosen != null) {
          return _reject(
            'Must provide operation name if query contains multiple '
            'operations.',
            DiagnosticCode.operationNameRequired,
          );
        }
        chosen = definition;
      } else if (definition.name?.value == operationName) {
        chosen = definition;
      }
    }
    if (chosen == null) {
      return operationName == null
          ? _reject('Must provide an operation.', DiagnosticCode.noOperation)
          : _reject(
              'Unknown operation named "$operationName".',
              DiagnosticCode.unknownOperation,
            );
    }
    return _checkRoot(chosen);
  }

  OperationSelectionResult _checkRoot(OperationDefinition operation) {
    if (schema.rootTypeName(operation.operation) == null) {
      return _reject(
        'Schema is not configured to execute ${operation.operation.name} '
        'operation.',
        DiagnosticCode.unsupportedOperationType,
      );
    }
    return OperationSelected(operation);
  }

  OperationRejected _reject(String message, DiagnosticCode code) =>
      OperationRejected(
        GraphQLError(
          message,
          extensions: JsonObject({'code': JsonString(code.id)}),
        ),
      );
}
