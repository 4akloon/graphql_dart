/// A value that may be absent, as an argument, input field or variable that
/// was not given, which GraphQL tells apart from an explicit `null`
/// (September2025 §6.4.1 "Coercing Variable Values" and the "Input Object"
/// input coercion; R4.4, R7.7).
///
/// ```dart
/// const name = Optional.present('Ada');
/// const none = Optional<String?>.absent();
/// ```
///
/// {@category protocol}
sealed class Optional<T> {
  /// A present [value], which may be `null` when [T] is nullable.
  const factory Optional.present(T value) = Present<T>;

  /// No value.
  const factory Optional.absent() = Absent<T>;
}

/// A present value of an [Optional].
///
/// {@category protocol}
final class const Present<T>(
  /// The value, `null` included when [T] is nullable.
  final T value,
) implements Optional<T> {
  /// Creates a present [value].
  this;

  @override
  bool operator ==(Object other) =>
      other is Present<Object?> && other.value == value;

  @override
  int get hashCode => Object.hash(Present, value);

  @override
  String toString() => 'Optional.present($value)';
}

/// The absence of a value in an [Optional].
///
/// {@category protocol}
final class const Absent<T>() implements Optional<T> {
  /// Creates the absence of a value.
  this;

  @override
  bool operator ==(Object other) => other is Absent<Object?>;

  @override
  int get hashCode => (Absent).hashCode;

  @override
  String toString() => 'Optional.absent()';
}
