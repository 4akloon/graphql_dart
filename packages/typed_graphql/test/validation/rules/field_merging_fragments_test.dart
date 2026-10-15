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

  test('a fragment that reaches a cycle, spread beside a field, conflicts '
      'inside it (and the cycle is reported too)', () {
    const text =
        '{ a { t { z: z ...F } ...F } } '
        'fragment F on I { z: y ...C } fragment C on I { ...C }';
    expect(
      checked
          .errors(text, const [
            OverlappingFieldsCanBeMergedRule(),
            NoFragmentCyclesRule(),
          ])
          .map((line) => line.split(' ')[1]),
      unorderedEquals(['GQL206', 'GQL216']),
    );
  });

  const tail =
      'Use different aliases on the fields to fetch both if this was '
      'intentional.';
  for (final (name, text, expected) in [
    (
      'a cycle behind a fragment spread beside a field',
      '{ a { t { z: z ...F } ...F } } '
          'fragment F on I { z: y ...C } fragment C on I { ...C }',
      [
        '1:11 GQL206 Fields "z" conflict because "z" and "y" are different fields.',
      ],
    ),
    (
      'a fragment that spreads itself',
      '{ a { ...F z: y } } fragment F on T { z: t { y } ...F }',
      [
        '1:12 GQL206 Fields "z" conflict because "y" and "t" are different fields.',
      ],
    ),
    (
      'two fragments that spread each other',
      '{ a { ...F } } fragment F on T { z: z ...G } '
          'fragment G on T { z: y ...F }',
      [
        '1:34 GQL206 Fields "z" conflict because "z" and "y" are different fields.',
      ],
    ),
    (
      'two fragments that spread each other, both spread',
      '{ a { ...F ...G } } fragment F on T { z: z ...G } '
          'fragment G on T { z: y ...F }',
      [
        '1:39 GQL206 Fields "z" conflict because "z" and "y" are different fields.',
      ],
    ),
    (
      'a fragment that spreads itself, without a conflict',
      '{ a { ...F } } fragment F on T { z: z ...F x: z }',
      <String>[],
    ),
  ]) {
    test('the messages of $name', () {
      expect(checked.errors(text, rules), [
        for (final message in expected) '$message $tail',
      ]);
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

  test('the rule agrees with a naive field merging on random documents with fragment cycles', () {
    final random = Random(20261016);
    // Not a valid schema (V.x is an Int, I.x a String): conflicts of shape.
    final schema = Built(RandomMergeDocument.sdl).schema;
    final validSchema = ValidSchema.assumeValid(schema);
    final generator = RandomMergeDocument(
      random,
      schema,
      hasCycles: true,
    );
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
      final expected = NaiveFieldMerging(schema, document, maxDepth: 6).isValid;
      if (!expected) invalid++;
      // A fragment on a cycle is not expanded again below itself, so the
      // rule may miss a conflict of a document that is invalid anyway
      // (GQL216); it never reports one the reference does not.
      if (!isValid) expect(expected, isFalse, reason: text);
    }
    expect(
      invalid,
      greaterThan(50),
      reason: 'the documents exercise conflicts',
    );
  });
}
