import '../../language/ast/selection.dart';
import '../../language/ast/selection_set.dart';
import '../../schema/model/schema_field.dart';
import '../../schema/model/schema_type.dart';
import '../validation_context.dart';
import 'field_origin.dart';
import 'fragment_path.dart';
import 'fragment_trail.dart';
import 'merge_item.dart';

/// Collects the fields selected under the items of a merged set, as
/// graphql-js's `getFieldsAndFragmentSpreads` collects one selection set:
/// its fields and inline fragments in order, then each spread fragment's
/// fields, depth first.
///
/// A fragment is expanded once per collection and not at all when it is on
/// the [path], so recursive fragments end. Each field charges one step.
final class SelectionCollector(
  /// The run the work is charged to and reported in.
  final ValidationContext context,

  /// The parent type and definition of each field of the document.
  final Map<Field, FieldOrigin> origins,
  final FragmentPath path,
) {
  /// Creates a collector that skips the fragments on [path].
  this;

  /// The fields under [sources] (each a selection set and the item it
  /// belongs to, null at the top of a definition) grouped by response
  /// name in first-seen order, and the fragments expanded to reach them.
  ({Map<String, List<MergeItem>> groups, List<String> expanded}) collect(
    List<(SelectionSet, MergeItem?)> sources,
  ) {
    final groups = <String, List<MergeItem>>{};
    // Insertion-ordered, so the path is entered and left in one order.
    final expanded = <String>{};
    for (final (selectionSet, parent) in sources) {
      final units = [(selectionSet, FragmentTrail.empty)];
      while (units.isNotEmpty && !context.isAborted) {
        final (set, trail) = units.removeLast();
        final spreads = _fields(set, (parent, trail), groups);
        final fragments = _newFragments(spreads, expanded);
        for (final (name, fragmentSet) in fragments.reversed) {
          units.add((fragmentSet, trail.inside(name)));
        }
      }
    }
    return (groups: groups, expanded: expanded.toList());
  }

  /// The fragments of [spreads] to expand, in order: known, not on the
  /// path and not yet in [expanded], to which they are added.
  List<(String, SelectionSet)> _newFragments(
    List<String> spreads,
    Set<String> expanded,
  ) {
    final fragments = <(String, SelectionSet)>[];
    for (final name in spreads) {
      if (path.contains(name) || expanded.contains(name)) continue;
      if (context.fragmentNamed(name) case final fragment?) {
        expanded.add(name);
        fragments.add((name, fragment.selectionSet));
      }
    }
    return fragments;
  }

  /// Adds the fields of [selectionSet] and of its inline fragments to
  /// [groups]; returns the names of the fragments it spreads, in order.
  List<String> _fields(
    SelectionSet selectionSet,
    (MergeItem?, FragmentTrail) place,
    Map<String, List<MergeItem>> groups,
  ) {
    final spreads = <String>[];
    final pending = [...selectionSet.selections.reversed];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case final Field field:
          if (_item(field, place) case final item?) {
            (groups[item.responseName] ??= []).add(item);
          }
        case InlineFragment(:final selectionSet):
          pending.addAll(selectionSet.selections.reversed);
        case FragmentSpread(:final name):
          spreads.add(name.value);
      }
    }
    return spreads;
  }

  MergeItem? _item(Field field, (MergeItem?, FragmentTrail) place) {
    final origin = origins[field];
    if (origin == null || !context.spend(1)) {
      return null;
    }
    final (parent, trail) = place;
    return MergeItem(field, origin, _definition(origin, field), parent, trail);
  }

  SchemaField? _definition(FieldOrigin origin, Field field) =>
      switch (origin.parentType) {
        final ObjectType type => type.fieldNamed(field.name.value),
        final InterfaceType type => type.fieldNamed(field.name.value),
        _ => null,
      };
}
