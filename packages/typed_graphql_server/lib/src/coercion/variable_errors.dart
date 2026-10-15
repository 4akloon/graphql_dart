import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_problem.dart';
import 'coercion_result.dart';
import 'unexpected_input_error.dart';

/// The request errors of one variable coercion run, with the limit of
/// `maxCoercionErrors`: the errors up to the limit, then, when one more
/// would follow, graphql-js's "Too many errors" error.
final class VariableErrors {
  /// Collects at most [maxErrors] errors, located in [source] when given.
  VariableErrors(this.maxErrors, this.source);

  static const String _tooMany =
      'Too many errors processing variables, error limit reached. '
      'Execution aborted.';

  /// The most errors kept before the "Too many errors" one.
  final int maxErrors;

  /// The text of the document, for the locations; null for none.
  final Source? source;

  /// The errors, in report order.
  final List<GraphQLError> errors = [];

  /// What user code threw, for `onError`.
  final List<UnexpectedInputError> unexpected = [];

  /// Whether the limit was reached and the run must stop.
  bool isStopped = false;

  /// How many more errors fit.
  int get remaining => maxErrors - errors.length;

  /// Records one error at [offset] of the document; past the limit it
  /// records the "Too many errors" error once instead.
  void report(String message, DiagnosticCode code, int? offset) {
    if (isStopped) {
      return;
    }
    if (errors.length >= maxErrors) {
      stop();
      return;
    }
    errors.add(_error(message, code, offset, null));
  }

  /// Records the problems of a failed coercion, each worded as
  /// `[subject][where]: [message]`.
  void reportFailure(
    CoercionFailure failure,
    String subject,
    DiagnosticCode code,
    int? offset,
  ) {
    for (final problem in failure.problems) {
      if (errors.length >= maxErrors) {
        stop();
        return;
      }
      _reportProblem(problem, subject, code, offset);
    }
    if (failure.hasOverflowed) {
      stop();
    }
  }

  /// Records the "Too many errors" error, once, and stops the run.
  void stop() {
    if (isStopped) {
      return;
    }
    isStopped = true;
    errors.add(
      _error(_tooMany, DiagnosticCode.tooManyVariableErrors, null, null),
    );
  }

  void _reportProblem(
    CoercionProblem problem,
    String subject,
    DiagnosticCode code,
    int? offset,
  ) {
    final text = '$subject${problem.where}: ${problem.message}';
    final reported = _error(
      text,
      problem.code ?? code,
      offset,
      problem.extensions,
    );
    errors.add(reported);
    if (problem.thrown case (:final error, :final stackTrace)?) {
      unexpected.add(UnexpectedInputError(error, stackTrace, reported));
    }
  }

  GraphQLError _error(
    String message,
    DiagnosticCode code,
    int? offset,
    JsonObject? extensions,
  ) {
    final text = source;
    return GraphQLError(
      message,
      locations: [if (text != null && offset != null) text.locationOf(offset)],
      extensions: extensions ?? JsonObject({'code': JsonString(code.id)}),
    );
  }
}
