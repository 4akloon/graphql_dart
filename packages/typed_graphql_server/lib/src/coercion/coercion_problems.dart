import 'package:typed_graphql/typed_graphql.dart';

import 'coercion_problem.dart';
import 'input_path.dart';

/// The problems found while coercing one value, up to a limit.
///
/// A problem past the limit is dropped and [hasOverflowed] is set, which
/// tells the coercion to stop looking (R0.3: the work on a hostile value
/// must not grow with its size).
final class CoercionProblems {
  /// Collects at most [limit] problems.
  CoercionProblems(this.limit);

  /// The most problems kept.
  final int limit;

  /// The problems kept, in report order.
  final List<CoercionProblem> kept = [];

  /// Whether a problem arrived after the limit was reached.
  bool hasOverflowed = false;

  /// Records [message] at [path].
  void add(
    String message,
    InputPath path, {
    DiagnosticCode? code,
    JsonObject? extensions,
    ({Object error, StackTrace stackTrace})? thrown,
  }) {
    if (kept.length >= limit) {
      hasOverflowed = true;
      return;
    }
    kept.add(
      CoercionProblem(
        message,
        path.description,
        code: code,
        extensions: extensions,
        thrown: thrown,
      ),
    );
  }
}
