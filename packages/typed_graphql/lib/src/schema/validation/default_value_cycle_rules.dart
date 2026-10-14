import '../../diagnostics/source_span.dart';
import '../../language/ast/value.dart';
import '../model/input_value.dart';
import '../model/schema_type.dart';
import '../schema.dart';
import 'node_span.dart';
import 'validation_report.dart';

/// The rule that no input field's default value contains itself (spec
/// §3.10, "default values must not form a cycle"), as graphql-js's
/// `createInputObjectDefaultValueCircularRefsValidator`: a depth-first
/// walk through the default values, with its own stack.
///
/// One instance serves one validation run: the fields it has walked are
/// remembered across input types, so a cycle is reported once and the run
/// costs linear time.
final class DefaultValueCycleRules {
  /// Creates the rule for [schema].
  DefaultValueCycleRules(this.report, this.schema);

  /// Receives the errors.
  final ValidationReport report;

  /// The schema checked.
  final Schema schema;

  final Set<String> _visited = {};

  // The fields whose default values are being walked, outermost first,
  // with the span of each default value; _positions indexes it by field.
  final List<(String, SourceSpan?)> _path = [];
  final Map<String, int> _positions = {};
  final Map<InputObjectType, List<_Target>> _targets = {};

  /// Reports the cycles reached from the fields of [type].
  void check(InputObjectType type) {
    final work = <_Work>[];
    _pushFields(work, type, const {});
    while (work.isNotEmpty && !report.isFull) {
      switch (work.removeLast()) {
        case _Literal(:final type, :final value):
          _literal(work, type, value);
        case _Field(:final field, :final coordinate, :final type):
          _field(work, field, coordinate, type);
        case _Leave(:final coordinate):
          _path.removeLast();
          _positions.remove(coordinate);
      }
    }
  }

  void _literal(List<_Work> work, InputObjectType type, Value value) {
    switch (value) {
      case ListValue(:final values):
        work.addAll([
          for (final item in values.reversed) _Literal(type, item),
        ]);
      case ObjectValue(:final fields):
        _pushFields(work, type, {
          for (final field in fields) field.name.value: field.value,
        });
      case _:
        break;
    }
  }

  // The fields given in [given] are walked through the given value, the
  // others through their own default values.
  void _pushFields(
    List<_Work> work,
    InputObjectType type,
    Map<String, Value> given,
  ) {
    final items = <_Work>[
      for (final (field, coordinate, target) in _targetsOf(type))
        if (given[field.name] case final value?)
          _Literal(target, value)
        else if (!_isSettled(coordinate))
          _Field(field, coordinate, target),
    ];
    work.addAll(items.reversed);
  }

  // The fields of input object types, computed once per type: a literal
  // with many objects must not scan the type's fields, build their
  // coordinates and resolve their types again for each of them.
  List<_Target> _targetsOf(InputObjectType type) => _targets[type] ??= [
    for (final field in type.fields)
      if (schema.namedTypeOf(field.type) case final InputObjectType target)
        (field, '${type.name}.${field.name}', target),
  ];

  // A walked field that is not on the path finds nothing more.
  bool _isSettled(String coordinate) =>
      _visited.contains(coordinate) && !_positions.containsKey(coordinate);

  void _field(
    List<_Work> work,
    InputValue field,
    String coordinate,
    InputObjectType type,
  ) {
    final defaultValue = field.defaultValue;
    if (defaultValue == null) return;
    if (_positions[coordinate] case final position?) {
      _report(coordinate, position);
      return;
    }
    if (!_visited.add(coordinate)) return;
    _positions[coordinate] = _path.length;
    _path.add((
      coordinate,
      const NodeSpan().within(field.span, defaultValue),
    ));
    work
      ..add(_Leave(coordinate))
      ..add(_Literal(type, defaultValue));
  }

  void _report(String coordinate, int position) {
    // A cycle's text costs its length; once the report is full nobody
    // reads it.
    if (report.isFull) return;
    final via = [for (final (name, _) in _path.skip(position + 1)) name];
    report.error(
      .defaultValueCycle,
      'Invalid circular reference. The default value of Input Object field '
      '$coordinate references itself'
      '${via.isEmpty ? '' : ' via the default values of: ${via.join(', ')}'}.',
      [for (final (_, span) in _path.skip(position)) span],
    );
  }
}

typedef _Target = (InputValue field, String coordinate, InputObjectType type);

sealed class _Work {}

final class _Literal(final InputObjectType type, final Value value)
    extends _Work {
  this;
}

final class _Field(
  final InputValue field,
  final String coordinate,
  final InputObjectType type,
) extends _Work {
  this;
}

// Ends the walk of a field's default value: the field leaves the path.
final class _Leave(final String coordinate) extends _Work {
  this;
}
