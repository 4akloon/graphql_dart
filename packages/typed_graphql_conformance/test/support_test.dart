import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'support/csv_table.dart';
import 'support/graphql_js_suite.dart';
import 'support/schema_port.dart';

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

    test('finds no files in a folder that does not exist', () {
      expect(GraphqlJsSuite.filesIn('no/such/__tests__'), isEmpty);
    });
  });

  group('SchemaPort', () {
    const port = SchemaPort();

    test('reads applied directives with their arguments', () {
      final [directive] = port.applied('@deprecated(reason: "old")');
      expect(directive.name, 'deprecated');
      expect(directive.argument('reason'), isA<StringValue>());
    });

    test('prints a schema it can build back', () {
      expect(port.printed(port.singleField('[Int!]')), '''
type Query {
  singleField: [Int!]
}''');
    });
  });
}
