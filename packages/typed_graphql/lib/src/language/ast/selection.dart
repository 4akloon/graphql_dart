import 'argument.dart';
import 'child_reader.dart';
import 'directive.dart';
import 'name.dart';
import 'node.dart';
import 'selection_set.dart';
import 'type_ref.dart';

/// One selection of a [SelectionSet] (spec §2.4).
///
/// {@category language}
sealed class const Selection({super.start, super.end}) extends Node {
  /// Creates a selection spanning `start` to `end`.
  this;
}

/// A field, `alias: name(arguments) @directives { selections }` (spec
/// §2.5).
///
/// {@category language}
final class Field(
  /// The alias, if any.
  final Name? alias,

  /// The field name.
  final Name name, {
  List<Argument> arguments = const [],
  List<Directive> directives = const [],

  /// The sub-selections; null for a leaf field.
  final SelectionSet? selectionSet,
  super.start,
  super.end,
}) extends Selection {
  /// Creates a field.
  this;

  /// The arguments, in source order.
  final List<Argument> arguments = List.unmodifiable(arguments);

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [
    ?alias,
    name,
    ...arguments,
    ...directives,
    ?selectionSet,
  ];

  /// The alias and the name are both [Name]s: two leading names are both,
  /// one is the name alone.
  @override
  Field rebuildFrom(ChildReader read) {
    final names = read.all<Name>();
    if (names.isEmpty || names.length > 2) {
      throw StateError('A field has one or two names, not ${names.length}.');
    }
    if (names.length == 1 && alias != null && identical(names.single, alias)) {
      throw StateError(
        'Removing a field name is ambiguous: the alias would become the '
        'name. Rewrite the Field instead.',
      );
    }
    return Field(
      names.length == 2 ? names.first : null,
      names.last,
      arguments: read.all(),
      directives: read.all(),
      selectionSet: read.optional(),
      start: start,
      end: end,
    );
  }
}

/// A fragment spread, `...Name @directives` (spec §2.8).
///
/// {@category language}
final class FragmentSpread(
  /// The fragment name.
  final Name name, {
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Selection {
  /// Creates a fragment spread.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [name, ...directives];

  @override
  FragmentSpread rebuildFrom(ChildReader read) => FragmentSpread(
    read.one(),
    directives: read.all(),
    start: start,
    end: end,
  );
}

/// An inline fragment, `... on Type @directives { selections }` (spec
/// §2.8.2).
///
/// {@category language}
final class InlineFragment(
  /// The type condition, if any.
  final NamedType? typeCondition,

  /// The selections.
  final SelectionSet selectionSet, {
  List<Directive> directives = const [],
  super.start,
  super.end,
}) extends Selection {
  /// Creates an inline fragment.
  this;

  /// The directives, in source order.
  final List<Directive> directives = List.unmodifiable(directives);

  @override
  List<Node> get children => [?typeCondition, ...directives, selectionSet];

  @override
  InlineFragment rebuildFrom(ChildReader read) => InlineFragment(
    read.optional(),
    directives: read.all(),
    read.one(),
    start: start,
    end: end,
  );
}
