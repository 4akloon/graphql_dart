// Ported from graphql-js src/language/__tests__/schemaCoordinateLexer-test.ts;
// see mapping/language.csv.
import 'package:test/test.dart';

import '../support/contain.dart';
import '../support/lexer_port.dart';

void main() {
  const port = LexerPort();
  const contain = Contain();

  group('SchemaCoordinateLexer', () {
    test('tracks a schema coordinate', () {
      expect(
        port.coordinateLexOne('Name.field'),
        contain({'kind': 'Name', 'start': 0, 'end': 4, 'value': 'Name'}),
      );
    });

    test('forbids ignored tokens', () {
      expect(port.coordinateSyntaxError('\nName.field', count: 1), {
        'message': 'Syntax Error: Invalid character: U+000A.',
        'locations': [
          {'line': 1, 'column': 1},
        ],
      });
    });

    test('lex reports a useful syntax errors', () {
      expect(port.coordinateSyntaxError('Foo .bar'), {
        'message': 'Syntax Error: Invalid character: " ".',
        'locations': [
          {'line': 1, 'column': 4},
        ],
      });
    });
  });
}
