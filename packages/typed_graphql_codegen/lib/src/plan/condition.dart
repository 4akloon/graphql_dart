/// A variable `@include` or `@skip` condition on a selection (spec §3.13).
final class const Condition(
  /// The variable name, without the `$`.
  final String variable,

  /// Whether it is `@include(if: $variable)`: selected when the variable is
  /// true. False for `@skip`, selected when the variable is false.
  final bool isInclude,
) {
  /// Creates a condition.
  this;

  @override
  bool operator ==(Object other) =>
      other is Condition &&
      other.variable == variable &&
      other.isInclude == isInclude;

  @override
  int get hashCode => Object.hash(variable, isInclude);

  @override
  String toString() => isInclude ? '\$$variable' : '!\$$variable';
}
