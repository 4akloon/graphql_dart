import 'package:typed_graphql/typed_graphql.dart';

import 'execution_run.dart';

/// The outcome of preparing an operation: planned, variables coerced.
sealed class PreparedOperation {
  const PreparedOperation();
}

/// The operation can run; [run] holds its plan and coerced variables.
final class OperationReady extends PreparedOperation {
  /// Wraps [run].
  const OperationReady(this.run);

  /// The execution state of the first run.
  final ExecutionRun run;
}

/// The operation cannot run; [error] is the request error.
final class OperationRefused extends PreparedOperation {
  /// Wraps [error].
  const OperationRefused(this.error);

  /// The request error to answer with.
  final RequestErrorResult error;
}
