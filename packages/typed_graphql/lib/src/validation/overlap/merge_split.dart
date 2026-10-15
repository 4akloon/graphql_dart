import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import 'argument_text.dart';
import 'field_shape.dart';
import 'merge_item.dart';
import 'merge_work.dart';

/// Splits a [MergeWork] into classes as XING's linear field-merging
/// algorithm does (the Sangria algorithm, R3.3), and lists the pairs that
/// may conflict.
///
/// Shape classes hold the fields of one response shape; a field without a
/// definition joins every class. Name classes hold the fields that select
/// the same field with the same arguments, within a group of fields whose
/// parent types may be the same object (graphql-js's mutual exclusion):
/// one group per object parent type, a field with another parent joining
/// every group. A field is paired with the first field of each other class
/// seen before it, so the work is the number of fields times the number of
/// classes, not of pairs. Each class is merged further on its own.
final class MergeSplit(
  /// The run the work is charged to and reported in.
  final ValidationContext context,

  /// The shapes of the fields' types.
  final FieldShape shapes,
  final ArgumentText arguments,
) {
  /// Creates the splitter.
  this;

  /// The pairs of [work] that may conflict and the works under it.
  ({List<(MergeItem, MergeItem)> pairs, List<MergeWork> parts}) split(
    MergeWork work,
  ) {
    final pairs = <(MergeItem, MergeItem)>[];
    final items = work.items;
    final byName = [
      if (work.checksNames)
        for (final group in _groups(items))
          ..._classes(group, _nameKeys(group), pairs),
    ];
    final byShape = work.checksShape
        ? _classes(items, [
            for (final item in items) shapes.of(item.definition),
          ], pairs)
        : const <List<MergeItem>>[];
    if (byName case [final names] when names.length == items.length) {
      if (byShape case [final shape] when shape.length == items.length) {
        return (pairs: pairs, parts: [work]);
      }
    }
    return (
      pairs: pairs,
      parts: [
        for (final names in byName) MergeWork(names, checksShape: false),
        for (final shape in byShape) MergeWork(shape, checksNames: false),
      ],
    );
  }

  List<String> _nameKeys(List<MergeItem> group) => [
    for (final item in group)
      '${item.node.name.value}(${arguments.of(item.node)})',
  ];

  /// The groups of [items] whose parent types may be the same object.
  List<List<MergeItem>> _groups(List<MergeItem> items) {
    final objects = Map<SchemaType, void>.identity();
    for (final item in items) {
      if (item.origin.parentType case final ObjectType type) {
        objects[type] = null;
      }
    }
    if (objects.length < 2) {
      return [items];
    }
    return [
      for (final type in objects.keys)
        [
          for (final item in items)
            if (item.origin.parentType case final parent
                when identical(parent, type) || parent is! ObjectType)
              item,
        ],
    ];
  }

  /// The classes of [items] by [keys] (null joins every class), in order
  /// of first appearance; adds to [pairs] each item with the first item of
  /// every other class seen before it.
  List<List<MergeItem>> _classes(
    List<MergeItem> items,
    List<String?> keys,
    List<(MergeItem, MergeItem)> pairs,
  ) {
    final firsts = <String, MergeItem>{};
    for (final (index, item) in items.indexed) {
      if (keys[index] case final key?) {
        if (!context.spend(firsts.length)) break;
        pairs.addAll([
          for (final MapEntry(key: other, value: first) in firsts.entries)
            if (other != key) (first, item),
        ]);
        firsts.putIfAbsent(key, () => item);
      }
    }
    if (firsts.isEmpty) {
      return [items];
    }
    return [
      for (final key in firsts.keys)
        [
          for (final (index, item) in items.indexed)
            if (keys[index] == key || keys[index] == null) item,
        ],
    ];
  }
}
