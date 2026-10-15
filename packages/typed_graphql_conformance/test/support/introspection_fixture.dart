import 'dart:convert';
import 'dart:io';

/// The result graphql-js's introspection-test expects of the introspection
/// query, adapted to this edition of the specification.
///
/// graphql-js 17 also has the working-draft parts of the spec (directive
/// deprecation, fragment variables); this edition's introspection types have
/// none of them, so they are dropped from the expectation.
final class IntrospectionFixture {
  /// Creates the reader.
  const IntrospectionFixture();

  static const Set<String> _draftMembers = {
    'isDeprecated',
    'deprecationReason',
    'FRAGMENT_VARIABLE_DEFINITION',
    'DIRECTIVE_DEFINITION',
  };

  /// The expected response.
  Map<String, Object?> expected() {
    final expected = jsonDecode(
      File(
        'test/execution/fixtures/introspection_query_result.json',
      ).readAsStringSync(),
    ) as Map<String, Object?>;
    final data = expected['data'] as Map<String, Object?>;
    final schema = data['__schema'] as Map<String, Object?>;
    for (final type in _maps(schema['types'])) {
      _dropDraftParts(type);
    }
    for (final directive in _maps(schema['directives'])) {
      if (directive['name'] == 'deprecated') {
        (directive['locations'] as List<Object?>).remove(
          'DIRECTIVE_DEFINITION',
        );
      }
    }
    return expected;
  }

  List<Map<String, Object?>> _maps(Object? list) =>
      (list as List<Object?>).cast<Map<String, Object?>>();

  void _dropDraftParts(Map<String, Object?> type) {
    switch (type['name']) {
      case '__Schema':
        for (final field in _maps(type['fields'])) {
          if (field['name'] == 'directives') {
            field['args'] = <Object?>[];
          }
        }
      case '__Directive':
        _maps(type['fields']).removeWhere(_isDraft);
      case '__DirectiveLocation':
        _maps(type['enumValues']).removeWhere(_isDraft);
    }
  }

  bool _isDraft(Map<String, Object?> member) =>
      _draftMembers.contains(member['name']);
}
