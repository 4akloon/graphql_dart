import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../schema/built.dart';
import '../checked.dart';
import '../naive_field_merging.dart';
import '../random_merge_document.dart';

// A fragment spread beside a field is not an ancestor of the field's
// subfields: it is expanded there too (spec §5.3.2).
void main() {
  final checked = Checked('''
type Query { a: T }
interface I { y: Int }
type T implements I { y: Int z: Int t: T }
''');
  const rules = [OverlappingFieldsCanBeMergedRule()];

  for (final (name, text) in [
    (
      'spread beside the field, after it',
      '{ a { t { z: z ...F } ...F } } fragment F on I { z: y }',
    ),
    (
      'spread beside the field, before it',
      '{ a { ...F t { z: z ...F } } } fragment F on I { z: y }',
    ),
    (
      'spread by another fragment too',
      '{ ...G a { t { z: z ...F } } } '
          'fragment G on Query { a { ...F } } fragment F on I { z: y }',
    ),
  ]) {
    test('a fragment $name conflicts inside the field', () {
      expect(
        checked.errors(text, rules).map((line) => line.split(' ')[1]),
        ['GQL206'],
      );
    });
  }

  test('the rule agrees with a naive field merging on random documents', () {
    final random = Random(20261015);
    // Not a valid schema (V.x is an Int, I.x a String): conflicts of shape.
    final schema = Built(RandomMergeDocument.sdl).schema;
    final validSchema = ValidSchema.assumeValid(schema);
    final generator = RandomMergeDocument(random, schema);
    var invalid = 0;
    for (var round = 0; round < 1500; round++) {
      final text = generator.next();
      final source = Source(text);
      final document = const Parser().parse(source).requireDocument();
      final result = const DocumentValidator(
        rules: rules,
      ).validate(validSchema, document, source: source);
      final isValid = !result.diagnostics.any(
        (diagnostic) =>
            diagnostic.code == DiagnosticCode.overlappingFieldsCanBeMerged,
      );
      final expected = NaiveFieldMerging(schema, document).isValid;
      if (!expected) invalid++;
      expect(isValid, expected, reason: text);
    }
    expect(
      invalid,
      greaterThan(50),
      reason: 'the documents exercise conflicts',
    );
  });
}
