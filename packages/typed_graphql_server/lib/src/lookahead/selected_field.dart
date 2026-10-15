import 'package:meta/meta.dart';

import '../builder/arguments.dart';
import '../builder/field_def.dart';
import '../coercion/coercion_result.dart';
import '../plan/field_plan.dart';
import 'field_selection.dart';

/// One field of a [FieldSelection]: what the request asked for under one
/// response key.
///
/// {@category lookahead}
final class SelectedField {
  /// Creates the field of [plans], the plans of one response key (one per
  /// object type that collected it), read with the coerced [variables] and
  /// the field tables [definitions].
  @internal
  SelectedField(
    List<FieldPlan> plans,
    Map<String, Object?> variables,
    Map<String, Map<String, FieldDef<Object?, Object?>>> definitions,
  ) : _plans = plans,
      _variables = variables,
      _definitions = definitions;

  final List<FieldPlan> _plans;
  final Map<String, Object?> _variables;
  final Map<String, Map<String, FieldDef<Object?, Object?>>> _definitions;

  /// The field's name in the schema, never the alias.
  String get name => _plans.first.fieldName;

  /// The key of the field in the response: the alias, else [name].
  String get responseKey => _plans.first.responseKey;

  /// The alias the request gave, null when it gave none.
  String? get alias => responseKey == name ? null : responseKey;

  /// The field's arguments with the request's variables substituted and the
  /// defaults applied, coerced when first read.
  ///
  /// An argument whose value fails coercion reads as absent: the executor
  /// reports the problem when the field runs, so nothing is lost. Reading
  /// a required argument that way throws, as reading any missing one does.
  // `late`: the arguments are coerced on first read, so a look-ahead that
  // never asks for them does not pay for them.
  late final Arguments arguments = _readArguments();

  /// The sub-selection of the field: empty for a leaf. For a field of an
  /// abstract type it holds the fields every possible type collects.
  // `late` for the same reason: the children are collected on first read.
  late final FieldSelection selection = FieldSelection.under(
    _plans,
    _variables,
    _definitions,
  );

  Arguments _readArguments() {
    final plan = _plans.first;
    final declared =
        _definitions[plan.parentType.name]?[plan.fieldName]?.args ?? const [];
    return switch (plan.argumentsFor(_variables)) {
      CoercionSuccess(:final value) => Arguments(
        declared,
        value as Map<String, Object?>,
      ),
      CoercionFailure() => Arguments(declared, const <String, Object?>{}),
    };
  }
}
