import '../../language/ast/selection.dart';
import '../validation_context.dart';
import 'conflict_tree.dart';
import 'field_conflict.dart';

/// The conflicts of field merging, one report per pair of distinct
/// ancestors over the whole document (graphql-js memoizes the pairs it
/// compared), reported in graphql-js's order.
final class ConflictReports(
  /// The run the work is charged to and reported in.
  final ValidationContext context,
) {
  /// Creates an empty set of reports.
  this;

  final Map<Field, Map<Field, ConflictTree>> _trees = Map.identity();
  final List<ConflictTree> _pending = [];
  int _count = 0;

  /// Whether as many reports as the run may hold are known, so the
  /// search can stop.
  bool get isFull => _count >= context.maxErrors;

  /// Adds [conflict] to the report of its pair of ancestors, starting
  /// that report when it is new.
  void add(FieldConflict conflict) {
    final (one, other) = (conflict.first[0].node, conflict.second[0].node);
    if (_trees[one]?[other] ?? _trees[other]?[one] case final tree?) {
      tree.add(conflict);
      return;
    }
    final tree = ConflictTree(conflict, _count++);
    (_trees[one] ??= Map.identity())[other] = tree;
    _pending.add(tree);
  }

  /// Reports the reports started since the last flush, ordered by the
  /// selection set graphql-js finds them in (so by definition, as
  /// graphql-js visits them), then by discovery.
  void flush() {
    _pending.sort(
      (a, b) => a.position != b.position
          ? a.position.compareTo(b.position)
          : a.sequence.compareTo(b.sequence),
    );
    for (final tree in _pending) {
      context.report(.overlappingFieldsCanBeMerged, tree.message, tree.nodes);
    }
    _pending.clear();
  }
}
