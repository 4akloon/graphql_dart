import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'parsed.dart';

void main() {
  const drafts = ParserOptions(allowDirectiveExtensions: true);

  group('type extensions', () {
    test('parses a schema extension with directives and root types', () {
      const text = 'extend schema @d { mutation: M }';
      final extension = Parsed(text).single<SchemaExtension>();
      expect(extension.directives.single.name.value, 'd');
      expect(extension.operationTypes.single.type.name.value, 'M');
      expect([extension.start, extension.end], [0, text.length]);
    });

    test('parses an object extension that only adds interfaces', () {
      final extension = Parsed(
        'extend type A implements B & C',
      ).single<ObjectTypeExtension>();
      expect(extension.name.value, 'A');
      expect(extension.interfaces.map((type) => type.name.value), ['B', 'C']);
      expect(extension.fields, isEmpty);
    });

    test('parses scalar, interface, union, enum and input extensions', () {
      final document = Parsed(
        'extend scalar S @d '
        'extend interface I { a: Int } '
        'extend union U = A '
        'extend enum E { V } '
        'extend input In { a: Int }',
      ).document;
      expect(document.definitions.map((definition) => definition.runtimeType), [
        ScalarTypeExtension,
        InterfaceTypeExtension,
        UnionTypeExtension,
        EnumTypeExtension,
        InputObjectTypeExtension,
      ]);
    });

    test('rejects a type extension that adds nothing', () {
      expect(Parsed('extend type Foo').errors, [
        '1:16 GQL008 Unexpected <EOF>.',
      ]);
    });

    test('rejects a schema extension that adds nothing', () {
      expect(Parsed('extend schema').errors, [
        '1:14 GQL008 Unexpected <EOF>.',
      ]);
    });

    test('rejects an extension of an unknown kind', () {
      expect(Parsed('extend foo').errors, [
        '1:8 GQL008 Unexpected Name "foo".',
      ]);
    });

    test('rejects a description on an extension', () {
      expect(Parsed('"d" extend type A @d').errors, [
        '1:1 GQL011 Unexpected description, only GraphQL definitions '
            'support descriptions.',
      ]);
    });
  });

  group('directive extensions', () {
    test('parse when the option is on', () {
      final extension = Parsed(
        'extend directive @foo @bar',
        options: drafts,
      ).single<DirectiveExtension>();
      expect(extension.name.value, 'foo');
      expect(extension.directives.single.name.value, 'bar');
    });

    test('are reported as working draft when the option is off', () {
      expect(Parsed('extend directive @foo @bar').errors, [
        '1:1 GQL014 Directive extensions are a working-draft feature; '
            'enable them with ParserOptions.allowDirectiveExtensions.',
      ]);
    });

    test('report once and let the next definition parse', () {
      final parsed = Parsed('extend directive @foo @bar type A { a: Int }');
      expect(parsed.errors, hasLength(1));
      expect(parsed.partial.definitions.single, isA<ObjectTypeDefinition>());
    });

    test('must add a directive', () {
      expect(Parsed('extend directive @foo', options: drafts).errors, [
        '1:22 GQL008 Unexpected <EOF>.',
      ]);
    });
  });

  group('directive definitions', () {
    test('accept directives and DIRECTIVE_DEFINITION with the option', () {
      final directive = Parsed(
        'directive @a @b on DIRECTIVE_DEFINITION',
        options: drafts,
      ).single<DirectiveDefinition>();
      expect(directive.directives.single.name.value, 'b');
      expect(directive.locations.single.value, 'DIRECTIVE_DEFINITION');
    });

    test('report their directives as working draft without it', () {
      expect(Parsed('directive @a @b on FIELD').errors, [
        '1:14 GQL014 Directives on a directive definition are a '
            'working-draft feature; enable them with '
            'ParserOptions.allowDirectiveExtensions.',
      ]);
    });

    test('report DIRECTIVE_DEFINITION as working draft without it', () {
      expect(Parsed('directive @a on DIRECTIVE_DEFINITION').errors, [
        '1:17 GQL014 The DIRECTIVE_DEFINITION location is a working-draft '
            'feature; enable it with ParserOptions.allowDirectiveExtensions.',
      ]);
    });
  });
}
