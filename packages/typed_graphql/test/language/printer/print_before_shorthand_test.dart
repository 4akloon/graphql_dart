import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';

void main() {
  // A `{` after a type or extension printed with no body would open its
  // body, so the anonymous query that follows keeps its keyword.
  const bodyless = [
    'enum on',
    'enum E',
    'type A',
    'type A implements B @d',
    'interface I',
    'input X',
    'extend type A @d',
    'extend interface I @d',
    'extend input X @d',
    'extend enum E @d',
    'extend schema @d',
  ];

  Document reparse(String text) => Parsed(text).document;

  for (final head in bodyless) {
    group('after "$head"', () {
      final document = reparse('$head query { a }');

      test('prints the query keyword', () {
        expect(const Printer().print(document), '$head\n\nquery {\n  a\n}');
      });

      test('prints text that parses back to an equivalent document', () {
        final printed = const Printer().print(document);
        expect(reparse(printed).isEquivalentTo(document), isTrue);
      });

      test('minifies to text that parses back', () {
        final minified = const Printer(isMinified: true).print(document);
        expect(minified, endsWith(' query{a}'));
        expect(reparse(minified).isEquivalentTo(document), isTrue);
      });
    });
  }

  test('prints the fuzzer document that failed to round trip', () {
    final document = reparse('enum on query { ... enum }');
    expect(
      const Printer().print(document),
      'enum on\n\nquery {\n  ...enum\n}',
    );
    expect(
      const Printer(isMinified: true).print(document),
      'enum on query{...enum}',
    );
  });

  group('keeps the shorthand', () {
    test('first in the document', () {
      expect(const Printer().print(reparse('query { a }')), '{\n  a\n}');
    });

    test('after a definition with a body', () {
      expect(
        const Printer().print(reparse('type A { f: Int } query { a }')),
        'type A {\n  f: Int\n}\n\n{\n  a\n}',
      );
    });

    test('after a definition that has no body in its grammar', () {
      expect(
        const Printer().print(reparse('scalar S union U = A query { a }')),
        'scalar S\n\nunion U = A\n\n{\n  a\n}',
      );
    });

    test('after another operation', () {
      expect(
        const Printer().print(reparse('query A { a } query { b }')),
        'query A {\n  a\n}\n\n{\n  b\n}',
      );
    });

    test('for a lone operation that follows a bodyless type', () {
      final operation = reparse('type A query { a }').definitions.last;
      expect(const Printer().print(operation), '{\n  a\n}');
    });
  });
}
