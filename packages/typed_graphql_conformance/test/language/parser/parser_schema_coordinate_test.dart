// Ported from graphql-js src/language/__tests__/parser-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';

import '../../support/parser_port.dart';

void main() {
  const port = ParserPort();

  Map<String, Object?> name(String value, int start, int end) => {
    'kind': 'Name',
    'loc': {'start': start, 'end': end},
    'value': value,
  };

  Map<String, Object?> error(String message, int column) => {
    'message': message,
    'locations': [
      {'line': 1, 'column': column},
    ],
  };

  group('Parser', () {
    group('parseSchemaCoordinate', () {
      test('parses Name', () {
        expect(port.parseSchemaCoordinate('MyType'), {
          'kind': 'TypeCoordinate',
          'loc': {'start': 0, 'end': 6},
          'name': name('MyType', 0, 6),
        });
      });

      test('parses Name . Name', () {
        expect(port.parseSchemaCoordinate('MyType.field'), {
          'kind': 'MemberCoordinate',
          'loc': {'start': 0, 'end': 12},
          'name': name('MyType', 0, 6),
          'memberName': name('field', 7, 12),
        });
      });

      test('rejects Name . Name . Name', () {
        expect(
          port.coordinateSyntaxError('MyType.field.deep'),
          error('Syntax Error: Expected <EOF>, found ".".', 13),
        );
      });

      test('parses Name . Name ( Name : )', () {
        expect(port.parseSchemaCoordinate('MyType.field(arg:)'), {
          'kind': 'ArgumentCoordinate',
          'loc': {'start': 0, 'end': 18},
          'name': name('MyType', 0, 6),
          'fieldName': name('field', 7, 12),
          'argumentName': name('arg', 13, 16),
        });
      });

      test('rejects Name . Name ( Name : Name )', () {
        expect(
          port.coordinateSyntaxError('MyType.field(arg: value)'),
          error('Syntax Error: Invalid character: " ".', 18),
        );
      });

      test('parses @ Name', () {
        expect(port.parseSchemaCoordinate('@myDirective'), {
          'kind': 'DirectiveCoordinate',
          'loc': {'start': 0, 'end': 12},
          'name': name('myDirective', 1, 12),
        });
      });

      test('parses @ Name ( Name : )', () {
        expect(port.parseSchemaCoordinate('@myDirective(arg:)'), {
          'kind': 'DirectiveArgumentCoordinate',
          'loc': {'start': 0, 'end': 18},
          'name': name('myDirective', 1, 12),
          'argumentName': name('arg', 13, 16),
        });
      });

      test('parses __Type', () {
        expect(port.parseSchemaCoordinate('__Type'), {
          'kind': 'TypeCoordinate',
          'loc': {'start': 0, 'end': 6},
          'name': name('__Type', 0, 6),
        });
      });

      test('parses Type.__metafield', () {
        expect(port.parseSchemaCoordinate('Type.__metafield'), {
          'kind': 'MemberCoordinate',
          'loc': {'start': 0, 'end': 16},
          'name': name('Type', 0, 4),
          'memberName': name('__metafield', 5, 16),
        });
      });

      test('parses Type.__metafield(arg:)', () {
        expect(port.parseSchemaCoordinate('Type.__metafield(arg:)'), {
          'kind': 'ArgumentCoordinate',
          'loc': {'start': 0, 'end': 22},
          'name': name('Type', 0, 4),
          'fieldName': name('__metafield', 5, 16),
          'argumentName': name('arg', 17, 20),
        });
      });

      test('rejects @ Name . Name', () {
        expect(
          port.coordinateSyntaxError('@myDirective.field'),
          error('Syntax Error: Expected <EOF>, found ".".', 13),
        );
      });
    });
  });
}
