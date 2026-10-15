import 'package:typed_graphql/typed_graphql.dart';

import 'error_behavior.dart';

/// The errors of one execution in the order they were recorded, and whether
/// the execution has halted.
final class ErrorLog {
  /// Creates an empty log that applies [behavior].
  ErrorLog(this.behavior);

  /// What an error does to the execution.
  final ErrorBehavior behavior;

  /// The errors recorded so far.
  final List<GraphQLError> errors = [];

  /// The error that ended the execution; null while it runs on.
  GraphQLError? haltError;

  /// Whether the execution has ended: nothing more is started or recorded.
  bool get isHalted => haltError != null;

  /// Records [error]; under [ErrorBehavior.halt] it also ends the execution.
  void record(GraphQLError error) {
    if (isHalted) {
      return;
    }
    errors.add(error);
    if (behavior == ErrorBehavior.halt) {
      haltError = error;
    }
  }

  /// Ends the execution with [error], whatever the behaviour.
  void halt(GraphQLError error) {
    if (isHalted) {
      return;
    }
    errors.add(error);
    haltError = error;
  }
}
