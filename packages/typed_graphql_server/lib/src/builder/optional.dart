/// A value that may be absent, for inputs where absence differs from `null`
/// (partial updates; R4.4).
///
/// {@category builder}
sealed class const Optional<T>() {
  /// Creates an optional value.
  this;
}

/// A value that was given, possibly `null` when [T] allows it.
///
/// {@category builder}
final class const Present<T>(
  /// The given value.
  final T value,
) extends Optional<T> {
  /// Holds [value].
  this;

  // Checks `Present<Object?>`, not `Present<T>`: two equal values with
  // different static types must stay equal.
  @override
  bool operator ==(Object other) =>
      other is Present<Object?> && other.value == value;

  @override
  int get hashCode => Object.hash(Present, value);

  @override
  String toString() => 'Present($value)';
}

/// A value that was not given.
///
/// It is an `Optional<Never>`, so it fits every `Optional<T>`.
///
/// {@category builder}
final class const Absent() extends Optional<Never> {
  /// The absent value.
  this;

  @override
  bool operator ==(Object other) => other is Absent;

  @override
  int get hashCode => (Absent).hashCode;

  @override
  String toString() => 'Absent()';
}
