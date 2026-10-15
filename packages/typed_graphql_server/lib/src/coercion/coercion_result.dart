import 'coercion_problem.dart';

/// The outcome of coercing one input value: the coerced Dart value, or
/// every reason it is invalid.
sealed class CoercionResult {
  const CoercionResult();
}

/// The value was valid; [value] is the Dart value (null for a GraphQL null).
final class CoercionSuccess extends CoercionResult {
  /// Wraps [value].
  const CoercionSuccess(this.value);

  /// The coerced value.
  final Object? value;
}

/// The value was invalid.
final class CoercionFailure extends CoercionResult {
  /// Creates a failure with its [problems].
  CoercionFailure(List<CoercionProblem> problems, {required this.hasOverflowed})
    : problems = List.unmodifiable(problems);

  /// The problems, in report order, at most the limit asked for.
  final List<CoercionProblem> problems;

  /// Whether more problems were found than [problems] holds.
  final bool hasOverflowed;
}
