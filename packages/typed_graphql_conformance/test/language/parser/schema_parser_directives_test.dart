// Ported from graphql-js src/language/__tests__/schema-parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../support/kitchen_sink.dart';
import '../../support/parser_port.dart';
import '../../support/schema_nodes.dart';

void main() {
  const port = ParserPort();
  const drafts = ParserPort(
    options: ParserOptions(allowDirectiveExtensions: true),
  );
  const nodes = SchemaNodes();

  group('Schema Parser', () {
    test('Directive definition', () {
      const body = 'directive @foo on OBJECT | INTERFACE';
      final document = port.parse(body);

      expect(
        document,
        nodes.document([
          {
            'kind': 'DirectiveDefinition',
            'description': null,
            'directives': null,
            'name': {
              'kind': 'Name',
              'value': 'foo',
              'loc': nodes.loc(11, 14),
            },
            'arguments': null,
            'repeatable': false,
            'locations': [
              {
                'kind': 'Name',
                'value': 'OBJECT',
                'loc': nodes.loc(18, 24),
              },
              {
                'kind': 'Name',
                'value': 'INTERFACE',
                'loc': nodes.loc(27, 36),
              },
            ],
            'loc': nodes.loc(0, 36),
          },
        ], nodes.loc(0, 36)),
      );
    });

    test('Repeatable directive definition', () {
      const body = 'directive @foo repeatable on OBJECT | INTERFACE';
      final document = port.parse(body);

      expect(
        document,
        nodes.document([
          {
            'kind': 'DirectiveDefinition',
            'description': null,
            'directives': null,
            'name': {
              'kind': 'Name',
              'value': 'foo',
              'loc': nodes.loc(11, 14),
            },
            'arguments': null,
            'repeatable': true,
            'locations': [
              {
                'kind': 'Name',
                'value': 'OBJECT',
                'loc': nodes.loc(29, 35),
              },
              {
                'kind': 'Name',
                'value': 'INTERFACE',
                'loc': nodes.loc(38, 47),
              },
            ],
            'loc': nodes.loc(0, 47),
          },
        ], nodes.loc(0, 47)),
      );
    });

    test('Directive with incorrect locations', () {
      expect(
        port.syntaxError(
          'directive @foo on FIELD | INCORRECT_LOCATION',
        ),
        {
          'message': 'Syntax Error: Unexpected Name "INCORRECT_LOCATION".',
          'locations': [
            {'line': 1, 'column': 27},
          ],
        },
      );
    });

    // Adapted: directive extensions are a working-draft feature, so the
    // parse enables them (ParserOptions.allowDirectiveExtensions).
    test('Directive extension', () {
      expect(
        drafts.parse('extend directive @foo @bar'),
        nodes.document([
          {
            'kind': 'DirectiveExtension',
            'name': nodes.nameNode('foo', nodes.loc(18, 21)),
            'directives': [
              {
                'kind': 'Directive',
                'name': nodes.nameNode('bar', nodes.loc(23, 26)),
                'arguments': null,
                'loc': nodes.loc(22, 26),
              },
            ],
            'loc': nodes.loc(0, 26),
          },
        ], nodes.loc(0, 26)),
      );
    });

    // Adapted: the kitchen sink holds directive extensions and directives
    // on a directive definition, which are working-draft features.
    test('parses kitchen sink schema', () {
      expect(() => drafts.document(KitchenSink.sdl), returnsNormally);
    });
  });
}
