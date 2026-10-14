import 'package:test/test.dart';

import 'support/csv_table.dart';
import 'support/graphql_js_suite.dart';

void main() {
  group('CsvTable', () {
    test('reads quoted fields with commas, quotes and CRLF', () {
      final table = CsvTable.parse(
        'a,b\r\n"x, y","say ""hi"""\r\n',
      );
      expect(table.rows, [
        {'a': 'x, y', 'b': 'say "hi"'},
      ]);
    });

    test('fills missing trailing fields with empty strings', () {
      expect(CsvTable.parse('a,b\nx').rows, [
        {'a': 'x', 'b': ''},
      ]);
    });

    test('rejects a record with more fields than the header', () {
      expect(() => CsvTable.parse('a,b\nx,y,z'), throwsFormatException);
    });
  });

  group('GraphqlJsSuite', () {
    test('names each test with the describe blocks around it', () {
      const source = '''
describe('Parser', () => {
  it('parses', () => {});
  describe('parseValue', () => {
    it('parses null value', () => {});
  });
  it('limits', () => {});
});
describe('isPunctuatorTokenKind', () => {
  it('returns true', () => {});
});
''';
      expect(GraphqlJsSuite.parse(source).tests, [
        ('Parser', 'parses'),
        ('Parser > parseValue', 'parses null value'),
        ('Parser', 'limits'),
        ('isPunctuatorTokenKind', 'returns true'),
      ]);
    });
  });
}
