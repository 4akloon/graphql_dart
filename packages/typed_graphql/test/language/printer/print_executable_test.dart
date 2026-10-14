import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';

void main() {
  const printer = Printer();

  String reprint(String text, {ParserOptions? options}) => printer.print(
    Parsed(text, options: options ?? const ParserOptions()).document,
  );

  group('executable definitions', () {
    test('prints an anonymous query as the shorthand', () {
      expect(reprint('query { id }'), '{\n  id\n}');
    });

    test('prints an operation with variables, directives and selections', () {
      const text =
          r'query Q($a: Int = 1 @d, $b: [String!]!) @op '
          '{ alias: f(x: 1) @skip(if: true) { ...F ... on T { a } '
          r'... @include(if: $a) { b } } }';
      expect(
        reprint(text),
        'query Q(\$a: Int = 1 @d, \$b: [String!]!) @op {\n'
        '  alias: f(x: 1) @skip(if: true) {\n'
        '    ...F\n'
        '    ... on T {\n'
        '      a\n'
        '    }\n'
        '    ... @include(if: \$a) {\n'
        '      b\n'
        '    }\n'
        '  }\n'
        '}',
      );
    });

    test('prints a described fragment', () {
      expect(
        reprint('"F" fragment F on T @d { a }'),
        '"F"\nfragment F on T @d {\n  a\n}',
      );
    });

    test('puts variables on separate lines when one has a description', () {
      expect(
        reprint(r'query Q("d" $a: Int, $b: Int) { a }'),
        'query Q(\n"d"\n\$a: Int\n\$b: Int\n) {\n  a\n}',
      );
    });

    test('wraps arguments that pass 80 columns', () {
      final text =
          '{ field(argument1: "${'a' * 30}", argument2: "${'b' * 30}") }';
      expect(
        reprint(text),
        '{\n'
        '  field(\n'
        '    argument1: "${'a' * 30}"\n'
        '    argument2: "${'b' * 30}"\n'
        '  )\n'
        '}',
      );
    });

    test('prints an empty selection set as braces', () {
      const drafts = ParserOptions(allowEmptySelectionSets: true);
      expect(reprint('{ a { } }', options: drafts), '{\n  a {}\n}');
    });
  });

  group('values', () {
    test('prints every scalar value', () {
      expect(
        reprint(r'{ f(a: 1, b: 1.5e3, c: true, d: null, e: E, g: $v) }'),
        '{\n  f(a: 1, b: 1.5e3, c: true, d: null, e: E, g: \$v)\n}',
      );
    });

    test('escapes a quoted string as graphql-js does', () {
      expect(
        printer.print(const StringValue('a"\\\n\u0001\u007f\u{1F600}')),
        r'"a\"\\\n\u0001\u007F'
        '\u{1F600}"',
      );
    });

    test('prints a block string with BlockString', () {
      expect(
        printer.print(const StringValue('a\nb', isBlock: true)),
        '"""\na\nb\n"""',
      );
    });

    test('wraps a list value that passes 80 columns', () {
      final item = '"${'x' * 30}"';
      expect(
        printer.print(Parsed('{ f(a: [$item, $item, $item]) }').document),
        contains('[\n      $item\n      $item\n      $item\n    ]'),
      );
    });

    test('puts a long object value in a block', () {
      final item = '"${'x' * 30}"';
      final source = Source('{a: $item, b: $item, c: $item}');
      final value = switch (const Parser().parseValue(source)) {
        ParseElementSuccess(:final value) => value,
        ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
      };
      expect(printer.print(value), '{\n  a: $item\n  b: $item\n  c: $item\n}');
    });
  });
}
