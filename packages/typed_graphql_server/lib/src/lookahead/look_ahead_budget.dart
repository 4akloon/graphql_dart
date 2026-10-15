import 'package:meta/meta.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../execution/graphql_exception.dart';

/// The steps a look-ahead may still spend: the run's own step counter, the
/// one `ExecutionOptions.maxSteps` limits, so a selection that fans out
/// through aliases and fragments cannot cost more than the request could.
final class LookAheadBudget {
  /// Spends through [spend], which says whether [steps] more fit; [message]
  /// is what the refusal says.
  @internal
  LookAheadBudget(this._spend, this._message);

  /// A budget that never refuses: a selection made outside an execution.
  static final LookAheadBudget unlimited = LookAheadBudget((_) => true, '');

  final bool Function(int steps) _spend;
  final String _message;

  /// Spends [steps], or throws a [GraphQLException] with the code `GQL337`:
  /// thrown inside a resolver, it becomes that field's error. A refused
  /// charge spends nothing, so the rest of the execution is unaffected.
  void charge(int steps) {
    if (_spend(steps)) {
      return;
    }
    throw GraphQLException(
      _message,
      extensions: JsonObject({
        'code': JsonString(DiagnosticCode.maxExecutionStepsExceeded.id),
      }),
    );
  }
}
