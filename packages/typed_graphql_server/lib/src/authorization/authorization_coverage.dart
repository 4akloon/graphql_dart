import '../execution/executable_schema.dart';

/// Finds the fields no authorization rule covers, for a test that fails
/// when a new field ships unguarded.
///
/// {@category authorization}
final class AuthorizationCoverage {
  /// Reads the rules of [schema].
  AuthorizationCoverage(ExecutableSchema<Object?> schema)
    : uncovered = _uncoveredOf(schema);

  /// The coordinates (`Type.field`) of the fields with no rule on the field
  /// or its type, `public` rules counted as rules; introspection is
  /// excluded. Sorted.
  final List<String> uncovered;

  static List<String> _uncoveredOf(ExecutableSchema<Object?> schema) {
    final result = <String>[];
    for (final MapEntry(key: typeName, value: fields)
        in schema.bindings.fields.entries) {
      if (typeName.startsWith('__')) continue;
      for (final MapEntry(key: name, value: field) in fields.entries) {
        if (name.startsWith('__') || field.authorization != null) continue;
        result.add('$typeName.$name');
      }
    }
    return List.unmodifiable(result..sort());
  }
}
