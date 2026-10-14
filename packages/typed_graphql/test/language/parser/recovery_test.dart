import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'parsed.dart';

void main() {
  List<String> fieldNames(Document document) => [
    for (final definition in document.definitions.cast<OperationDefinition>())
      for (final selection in definition.selectionSet.selections)
        (selection as Field).name.value,
  ];

  group('definitions', () {
    test('reports every broken definition and keeps the others', () {
      final parsed = Parsed('query { a(x: ) } query B { b } { c: } { d }');
      expect(parsed.errors, [
        '1:14 GQL008 Unexpected ")".',
        '1:37 GQL007 Expected Name, found "}".',
      ]);
      expect(fieldNames(parsed.partial), ['b', 'd']);
    });

    test('resumes at a keyword or a description at the top level', () {
      final parsed = Parsed('notAnOperation Foo "d" query { a }');
      expect(parsed.errors, ['1:1 GQL008 Unexpected Name "notAnOperation".']);
      expect(fieldNames(parsed.partial), ['a']);
    });

    test('a directive named like a keyword is not a definition start', () {
      final parsed = Parsed('extend directive @d @query type X {a: Int}');
      expect(parsed.errors, hasLength(1));
      expect(parsed.errors.single, contains('GQL014'));
      expect(parsed.partial.definitions.whereType<ObjectTypeDefinition>(), [
        isA<ObjectTypeDefinition>().having((t) => t.name.value, 'name', 'X'),
      ]);
    });

    test('a directive definition with a keyword-named directive has no '
        'second error', () {
      expect(Parsed('directive @d @query on FIELD').errors, hasLength(1));
    });

    test('an unterminated definition gives one error', () {
      expect(Parsed(r'query Q($a: Int').errors, [
        r'1:16 GQL007 Expected "$", found <EOF>.',
      ]);
    });
  });

  group('selections', () {
    test('drops a failed selection and keeps the rest', () {
      final parsed = Parsed('{ a(x: ) b c(y: {z: }) d }');
      expect(parsed.errors, [
        '1:8 GQL008 Unexpected ")".',
        '1:21 GQL008 Unexpected "}".',
      ]);
      expect(fieldNames(parsed.partial), ['b', 'd']);
    });

    test('adds nothing to a lexer error', () {
      final parsed = Parsed('{ a ~ b }');
      expect(parsed.errors, ['1:5 GQL001 Unexpected character: "~".']);
      expect(fieldNames(parsed.partial), ['a', 'b']);
    });

    test('a selection set whose every selection failed fails too', () {
      final parsed = Parsed('{ a { b(x: ) } c }');
      expect(parsed.errors, ['1:12 GQL008 Unexpected ")".']);
      expect(fieldNames(parsed.partial), ['c']);
    });

    test('an unclosed selection set fails the definition once', () {
      final parsed = Parsed('{ a { b }');
      expect(parsed.errors, ['1:10 GQL007 Expected Name, found <EOF>.']);
      expect(parsed.partial.definitions, isEmpty);
    });
  });

  group('limits', () {
    test('a document past maxDepth loses only the deep definition', () {
      const options = ParserOptions(maxDepth: 2);
      final parsed = Parsed('{ a { b { c } } } { d }', options: options);
      expect(parsed.errors, [
        '1:9 GQL010 Document nests deeper than 2 levels.',
      ]);
      expect(fieldNames(parsed.partial), ['d']);
    });

    test('maxTokens stops the parse with one error', () {
      const options = ParserOptions(maxTokens: 7);
      expect(Parsed('{ foo(bar: "baz") }', options: options).errors, [
        '1:19 GQL006 Document contains more than 7 tokens. Parsing aborted.',
      ]);
      const enough = ParserOptions(maxTokens: 8);
      expect(Parsed('{ foo(bar: "baz") }', options: enough).errors, isEmpty);
    });

    test('a full sink stops the parse', () {
      final diagnostics = Parsed('~ ' * 150).result.diagnostics;
      expect(diagnostics, hasLength(DiagnosticSink.defaultMaxErrors + 1));
      expect(diagnostics.last.code, DiagnosticCode.diagnosticLimitReached);
    });
  });

  group('resynchronisation', () {
    test('a header error skips the body of the failed definition', () {
      expect(fieldNames(Parsed(r'query Q($a: ) { b } { c }').partial), [
        'c',
      ]);
      expect(fieldNames(Parsed(r'query Q($a: ) { b }').partial), isEmpty);
      expect(fieldNames(Parsed('fragment F on { a }').partial), isEmpty);
      expect(
        fieldNames(Parsed('fragment F { a } { b }').partial),
        ['b'],
      );
      expect(
        fieldNames(Parsed(r'query Q($a: Int = ) { b } { c }').partial),
        ['c'],
      );
      expect(fieldNames(Parsed('typo Foo { a: Int }').partial), isEmpty);
    });

    test('a stray closer at the top level is skipped', () {
      final parsed = Parsed('} query { a }');
      expect(parsed.errors, ['1:1 GQL008 Unexpected "}".']);
      expect(fieldNames(parsed.partial), ['a']);
    });

    test('a stray closer inside a selection set is skipped', () {
      final parsed = Parsed('{ a ) b }');
      expect(parsed.errors, hasLength(1));
      expect(fieldNames(parsed.partial), ['a', 'b']);
    });

    test('an unclosed parenthesis swallows the later definitions', () {
      final parsed = Parsed(r'query Q($a: Int { b } query R { c }');
      expect(parsed.errors, hasLength(1));
      expect(parsed.partial.definitions, isEmpty);
    });
  });

  group('empty selection sets allowed', () {
    const options = ParserOptions(allowEmptySelectionSets: true);

    test('a set whose every selection failed drops the definition', () {
      for (final text in ['{ ~ }', '{ ... on }', '{ a @ }']) {
        expect(Parsed(text, options: options).partial.definitions, isEmpty);
      }
    });

    test('a genuinely empty set still parses as empty', () {
      final operation = Parsed(
        '{ }',
        options: options,
      ).single<OperationDefinition>();
      expect(operation.selectionSet.selections, isEmpty);
    });
  });
}
