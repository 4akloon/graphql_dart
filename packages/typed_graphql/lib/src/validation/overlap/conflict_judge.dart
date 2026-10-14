import '../../language/ast/executable_definition.dart';
import '../../language/printer/printer.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import 'argument_text.dart';
import 'field_conflict.dart';
import 'field_shape.dart';
import 'fragment_trail.dart';
import 'merge_item.dart';

/// Decides whether a pair of fields from one merged set conflicts as
/// graphql-js's `findConflict` would report it.
///
/// The pair is reported for its nearest pair of distinct ancestors, at the
/// selection set graphql-js finds it in: the innermost fragment both are
/// spread through, else their parent field's, else the top of [root]. It
/// is dropped when a pair of ancestors already conflicts, since graphql-js
/// does not compare the subfields of conflicting fields. Mutual exclusion
/// is computed from the ancestors down: once two parents are different
/// object types, names and arguments may differ.
final class ConflictJudge(
  /// The run the work is charged to and reported in.
  final ValidationContext context,

  /// The shapes of the fields' types.
  final FieldShape shapes,

  /// The canonical text of the fields' arguments.
  final ArgumentText arguments,

  /// The operation or fragment whose fields are being merged.
  final ExecutableDefinition root,
) {
  /// Creates the judge of the pairs found while merging [root].
  this;

  static const Printer _printer = Printer();

  /// The conflict of [pair] to report, or null.
  FieldConflict? judge((MergeItem, MergeItem) pair) {
    final (first, second) = _chains(pair);
    if (!context.spend(first.length)) {
      return null;
    }
    var isExclusive = false;
    for (final (index, one) in first.indexed) {
      final other = second[index];
      isExclusive = isExclusive || _areExclusive(one, other);
      final reason = _reason(one, other, isExclusive: isExclusive);
      if (index < first.length - 1 && reason != null) {
        return null;
      }
      if (index == first.length - 1 && reason != null) {
        final reverse = _reason(other, one, isExclusive: isExclusive) ?? '';
        return FieldConflict(
          first,
          second,
          reason,
          reverse,
          _position(first[0], second[0]),
        );
      }
    }
    return null;
  }

  /// The ancestors of the pair up to the nearest distinct pair, from that
  /// pair down to the fields.
  (List<MergeItem>, List<MergeItem>) _chains((MergeItem, MergeItem) pair) {
    final (first, second) = pair;
    final ones = [first];
    final others = [second];
    var (one, other) = (first.parent, second.parent);
    while (one != null && other != null && !identical(one, other)) {
      ones.add(one);
      others.add(other);
      (one, other) = (one.parent, other.parent);
    }
    return (ones.reversed.toList(), others.reversed.toList());
  }

  /// The offset of the selection set where graphql-js finds the conflict
  /// of [one] and [other], two fields of one merged set: the innermost
  /// fragment both are spread through, else their parent field's
  /// selection, else the top of [root]. Definitions do not overlap, so
  /// the offset also orders the reports by definition.
  int _position(MergeItem one, MergeItem other) {
    final shared = switch (FragmentTrail.innermostShared(
      one.trail,
      other.trail,
    )) {
      final String name => context.fragmentNamed(name)?.selectionSet,
      null => one.parent?.node.selectionSet,
    };
    return (shared ??
            switch (root) {
              OperationDefinition(:final selectionSet) => selectionSet,
              FragmentDefinition(:final selectionSet) => selectionSet,
            })
        .start;
  }

  bool _areExclusive(MergeItem one, MergeItem other) =>
      !identical(one.origin.parentType, other.origin.parentType) &&
      one.origin.parentType is ObjectType &&
      other.origin.parentType is ObjectType;

  String? _reason(
    MergeItem one,
    MergeItem other, {
    required bool isExclusive,
  }) {
    if (!isExclusive) {
      final (name, otherName) = (one.node.name.value, other.node.name.value);
      if (name != otherName) {
        return '"$name" and "$otherName" are different fields';
      }
      if (arguments.of(one.node) != arguments.of(other.node)) {
        return 'they have differing arguments';
      }
    }
    if ((one.definition, other.definition) case (final d1?, final d2?)
        when shapes.of(d1) != shapes.of(d2)) {
      return 'they return conflicting types "${_printer.print(d1.type)}" '
          'and "${_printer.print(d2.type)}"';
    }
    return null;
  }
}
