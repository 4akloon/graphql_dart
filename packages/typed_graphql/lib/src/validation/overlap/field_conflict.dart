import 'merge_item.dart';

/// Two fields that conflict, as graphql-js reports them: the chains of
/// fields from the nearest pair of distinct ancestors down to the pair,
/// the reason the pair conflicts, and where graphql-js finds it.
final class FieldConflict(
  /// The first chain, from the ancestor to the conflicting field.
  final List<MergeItem> first,

  /// The second chain, as long as [first].
  final List<MergeItem> second,

  /// Why the last fields of the chains conflict, such as
  /// `"a" and "b" are different fields`.
  final String reason,

  /// [reason] with the two fields named the other way round.
  final String reverseReason,

  /// The offset of the selection set whose visit reports the conflict in
  /// graphql-js, which orders the reports.
  final int position,
) {
  /// Creates a conflict.
  this;

  /// The same conflict seen from the second chain.
  FieldConflict get swapped =>
      FieldConflict(second, first, reverseReason, reason, position);
}
