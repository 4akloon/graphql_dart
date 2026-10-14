import '../../diagnostics/source_span.dart';
import 'validation_report.dart';

/// The rules every name of a schema follows: the name syntax (spec
/// §2.1.9), no `__` prefix outside the introspection types (spec §3.4),
/// and no enum value named `true`, `false` or `null` (spec §3.9).
///
/// A schema read from SDL always has names of valid syntax; one built in
/// code may not, so the syntax is checked with graphql-js's `assertName`
/// messages.
final class NameRules(
  /// Receives the errors.
  final ValidationReport report,
) {
  /// Creates the rules.
  this;

  static final RegExp _start = RegExp('^[_A-Za-z]');
  static final RegExp _syntax = RegExp(r'^[_A-Za-z][_0-9A-Za-z]*$');
  static const List<String> _reservedEnumValues = ['true', 'false', 'null'];

  /// Reports [name], defined at [span], when its syntax is invalid or it
  /// begins with `__`.
  void check(String name, SourceSpan? span) {
    if (name.isEmpty) {
      report.error(.invalidName, 'Expected name to be a non-empty string.', [
        span,
      ]);
    } else if (!_start.hasMatch(name)) {
      report.error(
        .invalidName,
        'Names must start with [_a-zA-Z] but "$name" does not.',
        [span],
      );
    } else if (!_syntax.hasMatch(name)) {
      report.error(
        .invalidName,
        'Names must only contain [_a-zA-Z0-9] but "$name" does not.',
        [span],
      );
    } else if (name.startsWith('__')) {
      report.error(
        .reservedName,
        'Name "$name" must not begin with "__", which is reserved by '
        'GraphQL introspection.',
        [span],
      );
    }
  }

  /// Reports the name of an enum value as [check] does, and also when it
  /// is `true`, `false` or `null`.
  void checkEnumValue(String name, SourceSpan? span) {
    check(name, span);
    if (_reservedEnumValues.contains(name)) {
      report.error(
        .reservedEnumValueName,
        'Enum values cannot be named: $name',
        [span],
      );
    }
  }
}
