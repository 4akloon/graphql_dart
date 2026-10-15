import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'checked.dart';

// Spec sections 8 and 11 of M4 (R0.3, R3.8): `MaxCostRule` shares the step
// budget and builds its tables once per run, not once per operation.
void main() {
  final checked = Checked('''
type Query { node: Node }
type Node { name: String child: Node }
''');
  const limit = Duration(seconds: 10);
  const count = 100000;
  const rules = DocumentValidator(rules: [MaxCostRule(maxCost: 1000000000000)]);

  DocumentValidationResult timed(String text) {
    final stopwatch = Stopwatch()..start();
    final result = checked.validate(text, validator: rules);
    expect(stopwatch.elapsed, lessThan(limit));
    return result;
  }

  String operations(String selections) => List.generate(
    count,
    (index) => 'query Q$index { node { $selections } }',
  ).join(' ');

  test('100000 operations are costed in time', () {
    expect(timed(operations('name')), isA<ValidDocument>());
  });

  test('100000 operations with many fields spend the step budget', () {
    final fields = [for (var i = 0; i < 12; i++) 'f$i: name'].join(' ');
    final result = timed(operations(fields)) as InvalidDocument;
    expect(result.diagnostics.single.code, DiagnosticCode.documentTooComplex);
  });

  test('1000 operations over a chain of 1000 fragments spend the step '
      'budget', () {
    final fragments = List.generate(
      1000,
      (index) =>
          'fragment F$index on Node { name ${index < 999 ? '...F${index + 1}' : ''} }',
    ).join(' ');
    final queries = List.generate(
      1000,
      (index) => 'query Q$index { node { ...F0 } }',
    ).join(' ');
    final result = timed('$queries $fragments') as InvalidDocument;
    expect(result.diagnostics.single.code, DiagnosticCode.documentTooComplex);
  });
}
