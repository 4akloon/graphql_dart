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

  group('minified pinned cases', () {
    test('keeps # inside a string', () {
      expect(minify('{ a(x: "#no") }'), '{a(x:"#no")}');
    });

    test('keeps the sign of a negative number', () {
      expect(minify('{ a(x: -1, y: -2.5) }'), '{a(x:-1 y:-2.5)}');
    });

    test('joins implements and union members with & and |', () {
      expect(
        minify('type T implements A & B { a: Int } union U = A | B'),
        'type T implements A&B{a:Int}union U=A|B',
      );
    });

    test('separates a spread from a preceding name', () {
      expect(
        minify('{ ...F @d ... on T { a } }'),
        '{...F@d ...on T{a}}',
      );
      expect(minify('{ a ...F }'), '{a ...F}');
    });

    test('is unchanged when minified again', () {
      final once = minify('query Q(\$a: Int) { a(x: 1) { ...F } }');
      expect(
        const Printer(isMinified: true).print(Parsed(once).document),
        once,
      );
    });
  });

  group('parse, print, parse', () {
    const texts = <String, String>{
      'executable':
          r'"Q" query Q("v" $a: [Int!] = [1] @d) @op { alias: f(x: {a: "s"}) '
          '{ ...F ... on T @d { a } b { } } } '
          'fragment F on T { c } '
          r'mutation M($a: Int) { b } subscription S { a } '
          r'{ a(x: 1.5e3 y: null z: true w: ENUM v: $c) }',
      'type system':
          'schema { query: Q } '
          '"""Long\n  description""" type T implements A & B @d '
          '{ "f" f("arg" a: Int = 1): String! } '
          'interface I implements J { a: Int } '
          'union U @d = | A | B '
          'enum E { A B @d } '
          'input In { a: Int = 1 b: [String] = ["x"] } '
          'scalar S @d '
          'directive @d(a: Int) @e repeatable on FIELD | DIRECTIVE_DEFINITION',
      'extensions':
          'extend type T @d extend directive @d @e '
          'extend union U = D extend enum E { C } '
          'extend input In { c: Int } extend interface I @d '
          'extend scalar S @d extend type T @d { f: Int }',
    };

    for (final MapEntry(key: name, value: text) in texts.entries) {
      final original = Parsed(text, options: drafts).document;

      test('$name: canonical output parses to an equivalent tree', () {
        final printed = const Printer().print(original);
        final reparsed = Parsed(printed, options: drafts).document;
        expect(reparsed.isEquivalentTo(original), isTrue);
      });

      test('$name: minified output parses to an equivalent tree', () {
        final printed = const Printer(isMinified: true).print(original);
        final reparsed = Parsed(printed, options: drafts).document;
        expect(reparsed.isEquivalentTo(original), isTrue);
      });

      test('$name: canonical output is stable when printed again', () {
        final printed = const Printer().print(original);
        final reparsed = Parsed(printed, options: drafts).document;
        expect(const Printer().print(reparsed), printed);
      });

      test('$name: minified output is stable when printed again', () {
        const printer = Printer(isMinified: true);
        final printed = printer.print(original);
        final reparsed = Parsed(printed, options: drafts).document;
        expect(printer.print(reparsed), printed);
      });
    }
  });
}
