/// The size a field's `sizedFields` give to the fields directly in its
/// selection set: each name in [names] has the list size [size].
final class SizedContext(
  /// The field names that take [size].
  final Set<String> names,

  /// The size of each of those fields.
  final double size,
) {
  /// Creates a context.
  this;

  /// Identifies the context in a memo: two contexts with the same key give a
  /// fragment the same cost.
  late final String key = '${(names.toList()..sort()).join(',')}#$size';
}
