/// The values of the variables that `@skip`, `@include` and `@defer` read in
/// one request, in the order the plan lists them: two requests with equal
/// keys collect the same fields (spec 6.3.2), so they share a plan node.
///
/// An entry is null when the request has no boolean for that variable; the
/// collection then reports the argument problem.
final class ConditionKey {
  /// Creates a key over [values].
  ConditionKey(List<bool?> values) : values = List.unmodifiable(values);

  /// The booleans, one per condition variable.
  final List<bool?> values;

  @override
  bool operator ==(Object other) {
    if (other is! ConditionKey || other.values.length != values.length) {
      return false;
    }
    for (var i = 0; i < values.length; i++) {
      if (values[i] != other.values[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(values);
}
