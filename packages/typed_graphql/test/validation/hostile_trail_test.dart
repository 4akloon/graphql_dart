import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'checked.dart';

// Spec section 8 of M4 (R0.3): finding where a conflict is reported walks
// the fragments each of its two fields is spread through, and that walk is
// charged to the step budget.
void main() {
  final checked = Checked('type Query { a: Int b: Int }');
  const length = 1500;
  const conflicts = 1500;

  test('conflicts between fields far down two fragment chains spend the '
      'step budget', () {
    String chain(String prefix, String field) => [
      for (var index = 0; index < length; index++)
        'fragment $prefix$index on Query { ...$prefix${index + 1} }',
      'fragment $prefix$length on Query { '
          '${List.filled(conflicts, 'x: $field').join(' ')} }',
    ].join('\n');
    final stopwatch = Stopwatch()..start();
    final result = checked.validate(
      '{ ...A0 ...B0 }\n${chain('A', 'a')}\n${chain('B', 'b')}',
      validator: const DocumentValidator(
        rules: [OverlappingFieldsCanBeMergedRule()],
        maxErrors: 100000,
      ),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      contains(DiagnosticCode.documentTooComplex),
    );
  });
}
