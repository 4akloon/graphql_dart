import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'checked.dart';

// Spec section 8 of M4 (R0.3, R3.3): a valid document within the parser's
// limits never reaches the step budget. A fragment spread under two fields,
// level after level, has 2^levels paths and graphql-js merges it linearly.
void main() {
  final checked = Checked('type Query { a: Query b: Query }');
  const levels = 25;

  DocumentValidationResult timed(String text) {
    final stopwatch = Stopwatch()..start();
    final result = checked.validate(text);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 20)));
    return result;
  }

  String fragments({String lastField = 'a { __typename }'}) => [
    for (var index = 0; index < levels; index++)
      'fragment F$index on Query { p: a { ...F${index + 1} } '
          'q: b { ...F${index + 1} } }',
    'fragment F$levels on Query { $lastField }',
  ].join('\n');

  test('a fragment spread under two fields, $levels levels, is valid', () {
    expect(timed('{ ...F0 }\n${fragments()}'), isA<ValidDocument>());
  });

  test('the conflict at the bottom of the fan-out is reported once', () {
    final result = timed(
      '{ ...F0 }\n${fragments(lastField: 'f: a { __typename } f: b { __typename }')}',
    ) as InvalidDocument;
    expect(result.diagnostics.map((d) => d.code), [
      DiagnosticCode.overlappingFieldsCanBeMerged,
    ]);
  });
}
