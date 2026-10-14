// Ported from graphql-js src/language/__tests__/parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../support/dedent.dart';
import '../../support/error_json.dart';
import '../../support/kitchen_sink.dart';
import '../../support/parser_port.dart';

void main() {
  const port = ParserPort();
  const dedent = Dedent();

  Map<String, Object?> error(String message, int line, int column) => {
    'message': message,
    'locations': [
      {'line': line, 'column': column},
    ],
  };

  void expectParses(String text) {
    expect(() => port.document(text), returnsNormally);
  }

  group('Parser', () {
    // Adapted: String(error) adds a printLocation excerpt, which arrives in
    // M2b; Dart checks the message, the position and the location.
    test('parse provides useful errors', () {
      final failure = const Parser().parse(Source('{')).diagnostics.first;

      expect(
        const ErrorJson().of(failure),
        error('Syntax Error: Expected Name, found <EOF>.', 1, 2),
      );
      expect(failure.span?.start, 1);

      expect(
        port.syntaxError('''

      { ...MissingOn }
      fragment MissingOn Type
    '''),
        error('Syntax Error: Expected "on", found Name "Type".', 3, 26),
      );
      expect(
        port.syntaxError('{ field: {} }'),
        error('Syntax Error: Expected Name, found "{".', 1, 10),
      );
      expect(
        port.syntaxError('notAnOperation Foo { field }'),
        error('Syntax Error: Unexpected Name "notAnOperation".', 1, 1),
      );
      expect(
        port.syntaxError('...'),
        error('Syntax Error: Unexpected "...".', 1, 1),
      );
      expect(
        port.syntaxError('{ ""'),
        error('Syntax Error: Expected Name, found String "".', 1, 3),
      );
    });

    // Adapted: the printLocation excerpt arrives in M2b; Dart checks the
    // message, the location and the source name.
    test('parse provides useful error when using source', () {
      final source = Source('query', name: 'MyQuery.graphql');
      final failure = const Parser().parse(source).diagnostics.first;

      expect(
        const ErrorJson().of(failure),
        error('Syntax Error: Expected "{", found <EOF>.', 1, 6),
      );
      expect(failure.span?.source.name, 'MyQuery.graphql');
    });

    test('limits by a maximum number of tokens', () {
      const three = ParserPort(options: ParserOptions(maxTokens: 3));
      const two = ParserPort(options: ParserOptions(maxTokens: 2));
      const eight = ParserPort(options: ParserOptions(maxTokens: 8));
      const seven = ParserPort(options: ParserOptions(maxTokens: 7));

      expect(() => three.document('{ foo }'), returnsNormally);
      expect(
        two.syntaxError('{ foo }')['message'],
        'Syntax Error: Document contains more than 2 tokens. '
        'Parsing aborted.',
      );
      expect(() => eight.document('{ foo(bar: "baz") }'), returnsNormally);
      expect(
        seven.syntaxError('{ foo(bar: "baz") }')['message'],
        'Syntax Error: Document contains more than 7 tokens. '
        'Parsing aborted.',
      );
    });

    // Adapted: Parser exposes no tokenCount; Lexer.tokenCount after reading
    // the same text is checked.
    test('exposes the tokenCount', () {
      int tokenCount(String text) {
        final lexer = Lexer(Source(text), DiagnosticSink());
        while (lexer.advance().kind != TokenKind.eof) {}
        return lexer.tokenCount;
      }

      expect(tokenCount('{ foo }'), 3);
      expect(tokenCount('{ foo(bar: "baz") }'), 8);
    });

    test('parses variable inline values', () {
      expectParses(r'{ field(complex: { a: { b: [ $var ] } }) }');
    });

    test('parses constant default values', () {
      expect(
        port.syntaxError(
          r'query Foo($x: Complex = { a: { b: [ $var ] } }) { field }',
        ),
        error(
          r'Syntax Error: Unexpected variable "$var" in constant value.',
          1,
          37,
        ),
      );
    });

    test('parses variable definition directives', () {
      expectParses(r'query Foo($x: Boolean = false @bar) { field }');
    });

    test('does not accept fragments named "on"', () {
      expect(
        port.syntaxError('fragment on on on { on }'),
        error('Syntax Error: Unexpected Name "on".', 1, 10),
      );
    });

    test('does not accept fragments spread of "on"', () {
      expect(
        port.syntaxError('{ ...on }'),
        error('Syntax Error: Expected Name, found "}".', 1, 9),
      );
    });

    test('does not allow "true", "false", or "null" as enum value', () {
      for (final word in ['true', 'false', 'null']) {
        expect(
          port.syntaxError('enum Test { VALID, $word }'),
          error(
            'Syntax Error: Name "$word" is reserved and cannot be used '
            'for an enum value.',
            1,
            20,
          ),
        );
      }
    });

    test('parses multi-byte characters', () {
      // Note: ਊ could be naively interpreted as two line-feed chars.
      final document = port.document('''
      # This comment has a ਊ multi-byte character.
      { field(arg: "Has a ਊ multi-byte character.") }
    ''');

      final operation = document.definitions.first as OperationDefinition;
      final field = operation.selectionSet.selections.first as Field;
      expect(
        (field.arguments.first.value as StringValue).value,
        'Has a ਊ multi-byte character.',
      );
    });

    test('parses kitchen sink', () {
      expectParses(KitchenSink.query);
    });

    test('allows non-keywords anywhere a Name is allowed', () {
      const nonKeywords = [
        'on',
        'fragment',
        'query',
        'mutation',
        'subscription',
        'true',
        'false',
      ];
      for (final keyword in nonKeywords) {
        // You can't define or reference a fragment named `on`.
        final fragmentName = keyword != 'on' ? keyword : 'a';
        expectParses('''
        query $keyword {
          ... $fragmentName
          ... on $keyword { field }
        }
        fragment $fragmentName on Type {
          $keyword($keyword: \$$keyword)
            @$keyword($keyword: $keyword)
        }
      ''');
      }
    });

    test('parses anonymous mutation operations', () {
      expectParses('''
      mutation {
        mutationField
      }
    ''');
    });

    test('parses anonymous subscription operations', () {
      expectParses('''
      subscription {
        subscriptionField
      }
    ''');
    });

    test('parses named mutation operations', () {
      expectParses('''
      mutation Foo {
        mutationField
      }
    ''');
    });

    test('parses named subscription operations', () {
      expectParses('''
      subscription Foo {
        subscriptionField
      }
    ''');
    });

    test('creates ast', () {
      final result = port.parse(
        dedent('''
          {
            node(id: 4) {
              id,
              name
            }
          }
        '''),
      );

      expect(result, {
        'kind': 'Document',
        'loc': {'start': 0, 'end': 40},
        'definitions': [
          {
            'kind': 'OperationDefinition',
            'description': null,
            'loc': {'start': 0, 'end': 40},
            'operation': 'query',
            'name': null,
            'variableDefinitions': null,
            'directives': null,
            'selectionSet': {
              'kind': 'SelectionSet',
              'loc': {'start': 0, 'end': 40},
              'selections': [
                {
                  'kind': 'Field',
                  'loc': {'start': 4, 'end': 38},
                  'alias': null,
                  'name': {
                    'kind': 'Name',
                    'loc': {'start': 4, 'end': 8},
                    'value': 'node',
                  },
                  'arguments': [
                    {
                      'kind': 'Argument',
                      'name': {
                        'kind': 'Name',
                        'loc': {'start': 9, 'end': 11},
                        'value': 'id',
                      },
                      'value': {
                        'kind': 'IntValue',
                        'loc': {'start': 13, 'end': 14},
                        'value': '4',
                      },
                      'loc': {'start': 9, 'end': 14},
                    },
                  ],
                  'directives': null,
                  'selectionSet': {
                    'kind': 'SelectionSet',
                    'loc': {'start': 16, 'end': 38},
                    'selections': [
                      {
                        'kind': 'Field',
                        'loc': {'start': 22, 'end': 24},
                        'alias': null,
                        'name': {
                          'kind': 'Name',
                          'loc': {'start': 22, 'end': 24},
                          'value': 'id',
                        },
                        'arguments': null,
                        'directives': null,
                        'selectionSet': null,
                      },
                      {
                        'kind': 'Field',
                        'loc': {'start': 30, 'end': 34},
                        'alias': null,
                        'name': {
                          'kind': 'Name',
                          'loc': {'start': 30, 'end': 34},
                          'value': 'name',
                        },
                        'arguments': null,
                        'directives': null,
                        'selectionSet': null,
                      },
                    ],
                  },
                },
              ],
            },
          },
        ],
      });
    });
  });
}
