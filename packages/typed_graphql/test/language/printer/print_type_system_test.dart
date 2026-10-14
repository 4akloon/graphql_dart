import 'package:test/test.dart';
import 'package:typed_graphql/src/language/ast/child_reader.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';

void main() {
  const printer = Printer();
  const drafts = ParserOptions(allowDirectiveExtensions: true);

  String reprint(String text) =>
      printer.print(Parsed(text, options: drafts).document);

  group('definitions', () {
    test('prints a described object type with multiline arguments', () {
      const text =
          '"""Type""" type T implements A & B @d '
          '{ "f" f("arg" a: Int = 1 @e): String! g(a: Int, b: [Int]): T }';
      expect(
        reprint(text),
        '"""Type"""\n'
        'type T implements A & B @d {\n'
        '  "f"\n'
        '  f(\n'
        '    "arg"\n'
        '    a: Int = 1 @e\n'
        '  ): String!\n'
        '  g(a: Int, b: [Int]): T\n'
        '}',
      );
    });

    test('prints every other kind of definition', () {
      const definitions = [
        'schema @d {\n  query: Q\n  mutation: M\n}',
        'scalar S @d',
        'interface I implements J {\n  a: Int\n}',
        'union U @d = A | B',
        'enum E {\n  A @d\n  B\n}',
        'input I {\n  a: Int = 1\n}',
        'directive @d(a: Int) @e repeatable on FIELD | DIRECTIVE_DEFINITION',
      ];
      expect(
        reprint(definitions.join(' ')),
        definitions.join('\n\n'),
      );
    });
  });

  group('extensions', () {
    test('prints every kind of extension', () {
      const extensions = [
        'extend schema @d {\n  query: Q\n}',
        'extend scalar S @d',
        'extend type T implements A {\n  a: Int\n}',
        'extend interface I @d',
        'extend union U = A',
        'extend enum E {\n  A\n}',
        'extend input I {\n  a: Int\n}',
        'extend directive @d @e',
      ];
      expect(reprint(extensions.join(' ')), extensions.join('\n\n'));
    });
  });

  group('foreign nodes', () {
    test('a node this library does not define is an argument error', () {
      expect(() => printer.print(_ForeignNode()), throwsArgumentError);
    });

    test('a definition this library does not define is an argument error', () {
      expect(
        () => printer.print(Document([_ForeignDefinition()])),
        throwsArgumentError,
      );
    });
  });
}

/// A node that only a user of the library could define.
final class _ForeignNode extends Node {
  @override
  List<Node> get children => const [];

  @override
  Node rebuildFrom(ChildReader read) => this;
}

/// A definition that only a user of the library could define.
final class _ForeignDefinition extends Definition {
  @override
  List<Node> get children => const [];

  @override
  Node rebuildFrom(ChildReader read) => this;
}
