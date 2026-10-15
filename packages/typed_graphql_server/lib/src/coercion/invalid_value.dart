/// What a coercion step returns, instead of a value, for an input that is
/// invalid; its problem is already recorded. It is not `null`, which is a
/// valid GraphQL value.
final class InvalidValue {
  const InvalidValue._();

  /// The only instance.
  static const InvalidValue instance = InvalidValue._();
}
