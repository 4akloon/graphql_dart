import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';

void main() {
  const drafts = ParserOptions(
    allowDirectiveExtensions: true,
    allowEmptySelectionSets: true,
  );

  String minify(String text) =>
      const Printer(isMinified: true).print(Parsed(text).document);

  group('minified', () {
    test('drops whitespace and commas between punctuators', () {
      expect(
        minify(r'query Q($a: Int) { a(x: 1, y: "s") { ...F } }'),
        r'query Q($a:Int){a(x:1 y:"s"){...F}}',
      );
    });

    test('keeps one space between names and before a spread', () {
      expect(minify('{ a ...F }'), '{a ...F}');
    });

    test('prints block strings in their shortest form', () {
      expect(
        minify('"""\n  a\n  b\n""" type T { f: Int }'),
        '"""a\nb""" type T{f:Int}',
      );
    });
  });

  group('parse, print, parse', () {
    const text =
        r'"Q" query Q("v" $a: [Int!] = [1] @d) @op { alias: f(x: {a: "s"}) '
        '{ ...F ... on T @d { a } b { } } } '
        'fragment F on T { c } '
        'schema { query: Q } '
        '"""Long\n  description""" type T implements A & B @d '
        '{ "f" f("arg" a: Int = 1): String! } '
        'directive @d(a: Int) @e repeatable on FIELD | DIRECTIVE_DEFINITION '
        'extend type T @d extend directive @d @e';
    final original = Parsed(text, options: drafts).document;

    test('canonical output parses to an equivalent tree', () {
      final printed = const Printer().print(original);
      final reparsed = Parsed(printed, options: drafts).document;
      expect(reparsed.isEquivalentTo(original), isTrue);
    });

    test('minified output parses to an equivalent tree', () {
      final printed = const Printer(isMinified: true).print(original);
      final reparsed = Parsed(printed, options: drafts).document;
      expect(reparsed.isEquivalentTo(original), isTrue);
    });

    test('canonical output is stable when printed again', () {
      final printed = const Printer().print(original);
      final reparsed = Parsed(printed, options: drafts).document;
      expect(const Printer().print(reparsed), printed);
    });
  });
}
