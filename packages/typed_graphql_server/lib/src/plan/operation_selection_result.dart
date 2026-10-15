import 'package:typed_graphql/typed_graphql.dart';

/// The outcome of choosing the operation to run.
sealed class OperationSelectionResult {
  const OperationSelectionResult();
}

/// The operation to execute.
final class OperationSelected extends OperationSelectionResult {
  /// Wraps [operation].
  const OperationSelected(this.operation);

  /// The chosen operation.
  final OperationDefinition operation;
}

/// No operation can run; [error] is the request error.
final class OperationRejected extends OperationSelectionResult {
  /// Wraps [error].
  const OperationRejected(this.error);

  /// The request error, with its `GQL32x` code in `extensions`.
  final GraphQLError error;
}
