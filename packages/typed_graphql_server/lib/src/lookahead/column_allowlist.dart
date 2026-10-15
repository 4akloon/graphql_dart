import 'field_selection.dart';

/// Maps GraphQL field names to database columns, so a resolver selects only
/// the columns the request needs (R4.18). It reads a [FieldSelection]; it
/// preloads nothing and writes no SQL.
///
/// {@category lookahead}
final class ColumnAllowlist {
  /// Maps each field name in [columns] to its column; the [always] columns
  /// are in every answer (a key, say).
  ColumnAllowlist(Map<String, String> columns, {List<String> always = const []})
    : _columns = Map.unmodifiable(columns),
      _always = List.unmodifiable(always);

  final Map<String, String> _columns;
  final List<String> _always;

  /// The columns of the fields [selection] selects at its own level that the
  /// map knows, plus the always ones, sorted and without repeats. Fields the
  /// map does not know are ignored.
  List<String> columnsFor(FieldSelection selection) {
    final columns = <String>{..._always};
    for (final field in selection.fields) {
      if (_columns[field.name] case final column?) {
        columns.add(column);
      }
    }
    return columns.toList()..sort();
  }
}
