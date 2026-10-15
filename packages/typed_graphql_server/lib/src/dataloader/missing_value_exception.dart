/// Thrown into the future of a key that the batch function left out and whose
/// value type cannot be null.
///
/// A resolver that lets it escape is masked like any other resolver error.
///
/// {@category dataloader}
final class MissingValueException implements Exception {
  /// Creates the exception for [key].
  const MissingValueException(this.key);

  /// The key the batch function returned no value for.
  final Object? key;

  @override
  String toString() =>
      'MissingValueException: the batch function returned no value for key '
      '$key';
}
