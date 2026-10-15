import 'package:meta/meta.dart';

import '../builder/field_def.dart';
import '../plan/field_plan.dart';
import 'selected_field.dart';
import 'selection_fingerprint.dart';
import 'selection_nodes.dart';

/// The fields the request selected under a field, as the resolver of that
/// field sees them (R4.18): fragments flattened, `@skip` and `@include`
/// applied with the request's variables, `__typename` and the other meta
/// fields left out.
///
/// It is a view of the operation plan: nothing is collected until a member
/// is read, and a selection never changes.
///
/// {@category lookahead}
final class FieldSelection {
  /// Creates the selection under [plans], the plans of one response key, read
  /// with the coerced [variables] and the field tables [definitions]. Only the
  /// object type called [typeName] when it is given.
  @internal
  FieldSelection.under(
    List<FieldPlan> plans,
    Map<String, Object?> variables,
    Map<String, Map<String, FieldDef<Object?, Object?>>> definitions, [
    String? typeName,
  ]) : _plans = plans,
       _variables = variables,
       _definitions = definitions,
       _typeName = typeName;

  /// A selection with no fields: what a field of a leaf type, or a call
  /// made outside an execution, has.
  static final FieldSelection empty = FieldSelection.under(
    const [],
    const {},
    const {},
  );

  final List<FieldPlan> _plans;
  final Map<String, Object?> _variables;
  final Map<String, Map<String, FieldDef<Object?, Object?>>> _definitions;
  final String? _typeName;

  /// The selected fields in collection order, merged by response key. For
  /// a field of an abstract type these are the fields every possible type
  /// collects, in possible-type order; an alias keeps each occurrence apart.
  // `late`: collected on first read, so an unread selection costs nothing.
  late final List<SelectedField> fields = _collect();

  /// The selection restricted to the object type called [typeName].
  ///
  /// An unknown name, or a type the field's value cannot have, gives an
  /// empty selection; nothing throws.
  FieldSelection forType(String typeName) =>
      FieldSelection.under(_plans, _variables, _definitions, typeName);

  /// Whether the request selected the path [path] of field names (not
  /// aliases) joined by dots, as in `posts.comments.author`.
  ///
  /// An empty path or an empty segment is an [ArgumentError].
  bool has(String path) {
    var level = <FieldSelection>[this];
    for (final segment in path.split('.')) {
      if (segment.isEmpty) {
        throw ArgumentError.value(path, 'path', 'has an empty segment');
      }
      level = [
        for (final selection in level)
          for (final field in selection.fields)
            if (field.name == segment) field.selection,
      ];
    }
    return level.isNotEmpty;
  }

  /// Every selected field called [name] in the schema, whatever its alias.
  List<SelectedField> fieldsNamed(String name) => [
    for (final field in fields)
      if (field.name == name) field,
  ];

  /// A canonical text of the selection, equal for two selections that ask
  /// for the same fields with the same arguments: field names (not aliases)
  /// and arguments sorted, argument values as JSON with sorted keys and the
  /// variables substituted. Meant as a cache or DataLoader key.
  String get fingerprint => const SelectionFingerprint().of(this);

  List<SelectedField> _collect() {
    final byKey = <String, List<FieldPlan>>{};
    for (final node in const SelectionNodes().of(_plans, _typeName)) {
      for (final plan in node.fields) {
        if (plan.fieldName.startsWith('__')) {
          continue;
        }
        (byKey[plan.responseKey] ??= []).add(plan);
      }
    }
    return List.unmodifiable([
      for (final plans in byKey.values)
        SelectedField(plans, _variables, _definitions),
    ]);
  }
}
