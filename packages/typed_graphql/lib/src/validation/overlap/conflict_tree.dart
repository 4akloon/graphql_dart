import '../../language/ast/node.dart';
import '../../language/ast/selection.dart';
import 'field_conflict.dart';

/// One reported conflict of two fields with all the conflicts found
/// between their subfields: graphql-js's nested `Conflict`, as a tree of
/// field pairs whose leaves hold the reasons.
///
/// The message and the nodes are built with stacks, so a conflict 100000
/// levels deep cannot overflow the call stack.
final class ConflictTree {
  /// Starts the tree of [conflict], whose first chain gives the side of
  /// every later conflict; [sequence] orders reports found at one
  /// position.
  ConflictTree(FieldConflict conflict, this.sequence)
    : position = conflict.position,
      _root = _Pair(conflict.first[0].node, conflict.second[0].node) {
    add(conflict);
  }

  /// The offset of the selection set where graphql-js reports it.
  final int position;

  /// The order in which the tree was started.
  final int sequence;

  final _Pair _root;

  /// Adds the pairs of [conflict], whose chains start at this tree's two
  /// fields in either order, and its reason; a pair added before is kept.
  void add(FieldConflict conflict) {
    final oriented = identical(conflict.first[0].node, _root.first)
        ? conflict
        : conflict.swapped;
    var pair = _root;
    for (var level = 1; level < oriented.first.length; level++) {
      pair = pair.child(
        oriented.first[level].node,
        oriented.second[level].node,
      );
    }
    if (pair.children.isEmpty) {
      pair.reason ??= oriented.reason;
    }
  }

  /// graphql-js's message: the response name and the nested reasons.
  String get message {
    final buffer = StringBuffer(
      'Fields "${_responseName(_root.first)}" conflict because ',
    );
    final pending = <Object>[_root];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case final String text:
          buffer.write(text);
        case _Pair(:final reason?):
          buffer.write(reason);
        case _Pair(:final children):
          for (final (index, child) in children.indexed.toList().reversed) {
            pending.addAll([
              child,
              'subfields "${_responseName(child.first)}" conflict because ',
              if (index > 0) ' and ',
            ]);
          }
      }
    }
    buffer.write(
      '. Use different aliases on the fields to fetch both if this was '
      'intentional.',
    );
    return buffer.toString();
  }

  /// The fields of the first side in pre-order, then those of the second,
  /// as graphql-js lists a conflict's nodes.
  List<Node> get nodes => [..._side(isFirst: true), ..._side(isFirst: false)];

  List<Field> _side({required bool isFirst}) {
    final fields = <Field>[];
    final pending = [_root];
    while (pending.isNotEmpty) {
      final pair = pending.removeLast();
      fields.add(isFirst ? pair.first : pair.second);
      pending.addAll(pair.children.reversed);
    }
    return fields;
  }

  String _responseName(Field field) => field.alias?.value ?? field.name.value;
}

/// A pair of fields in a [ConflictTree]: a leaf with the reason they
/// conflict, or the pairs of their subfields that do.
final class _Pair(final Field first, final Field second) {
  /// Why the pair conflicts; null while it is not a leaf.
  String? reason;
  final List<_Pair> children = [];
  final Map<Field, Map<Field, _Pair>> _index = Map.identity();

  /// The pair of [one] and [other] under this one, added when new.
  _Pair child(Field one, Field other) {
    final byOther = _index[one] ??= Map.identity();
    if (byOther[other] case final pair?) {
      return pair;
    }
    final pair = _Pair(one, other);
    children.add(pair);
    return byOther[other] = pair;
  }
}
