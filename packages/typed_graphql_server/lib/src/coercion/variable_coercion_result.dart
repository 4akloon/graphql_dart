import 'package:typed_graphql/typed_graphql.dart';

import 'unexpected_input_error.dart';

/// The outcome of coercing the variables of an operation.
sealed class VariableCoercionResult {
  const VariableCoercionResult();
}

/// Every variable was valid. A variable the request did not give and that
/// has no default is not in [values].
final class CoercedVariables extends VariableCoercionResult {
  /// Wraps [values], a map the caller no longer changes.
  CoercedVariables(Map<String, Object?> values)
    : values = Map.unmodifiable(values);

  /// The coerced values by variable name (without the `$`).
  final Map<String, Object?> values;
}

/// Some variable was invalid; the operation does not run.
final class VariableCoercionFailure extends VariableCoercionResult {
  /// Creates a failure with its [errors] and the [unexpected] errors user
  /// code threw on the way.
  VariableCoercionFailure(
    List<GraphQLError> errors,
    List<UnexpectedInputError> unexpected,
  ) : errors = List.unmodifiable(errors),
      unexpected = List.unmodifiable(unexpected);

  /// The request errors, each with `extensions.code`, at most the limit
  /// and then one "Too many errors" error.
  final List<GraphQLError> errors;

  /// What user code threw (an input object's `decode`, a codec) that is
  /// masked in [errors]; the caller reports each to `onError`.
  final List<UnexpectedInputError> unexpected;
}
