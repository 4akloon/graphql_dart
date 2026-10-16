import 'package:test/test.dart';
import 'package:typed_graphql_server/src/upload/content_disposition.dart';

void main() {
  group('ContentDisposition.parse', () {
    test('reads the name', () {
      expect(ContentDisposition.parse('form-data; name="a"')?.name, 'a');
    });

    test('reads the file name', () {
      final parsed = ContentDisposition.parse(
        'form-data; name="a"; filename="b.txt"',
      );
      expect(parsed?.filename, 'b.txt');
    });

    test('has no file name when the header names none', () {
      expect(ContentDisposition.parse('form-data; name="a"')?.filename, isNull);
    });

    test('keeps an empty file name', () {
      final parsed = ContentDisposition.parse(
        'form-data; name="a"; filename=""',
      );
      expect(parsed?.filename, '');
    });

    test('unescapes a quote and a backslash in a quoted string', () {
      final parsed = ContentDisposition.parse(
        r'form-data; name="a\"b"; filename="c\\d"',
      );
      expect(parsed?.name, 'a"b');
      expect(parsed?.filename, r'c\d');
    });

    test('keeps a semicolon inside a quoted string', () {
      final parsed = ContentDisposition.parse('form-data; name="a;b"');
      expect(parsed?.name, 'a;b');
    });

    test('reads a value that is not quoted', () {
      expect(ContentDisposition.parse('form-data; name=a')?.name, 'a');
    });

    test('ignores filename*', () {
      final parsed = ContentDisposition.parse(
        "form-data; name=\"a\"; filename*=UTF-8''x.txt",
      );
      expect(parsed?.filename, isNull);
    });

    test('ignores the case of the type and of the parameter names', () {
      final parsed = ContentDisposition.parse('Form-Data; NAME="a"');
      expect(parsed?.name, 'a');
    });

    test('ignores spaces around the separators', () {
      final parsed = ContentDisposition.parse(
        '  form-data ;name = "a" ;  filename="b"  ',
      );
      expect(parsed?.name, 'a');
      expect(parsed?.filename, 'b');
    });

    test('ignores a parameter it does not know', () {
      final parsed = ContentDisposition.parse('form-data; x=1; name="a"');
      expect(parsed?.name, 'a');
    });

    test('is null for another type', () {
      expect(ContentDisposition.parse('attachment; name="a"'), isNull);
    });

    test('is null without a name', () {
      expect(ContentDisposition.parse('form-data; filename="a"'), isNull);
    });

    test('is null for a missing header', () {
      expect(ContentDisposition.parse(null), isNull);
    });

    test('is null for an empty header', () {
      expect(ContentDisposition.parse(''), isNull);
    });

    test('is null for a quoted string that is not closed', () {
      expect(ContentDisposition.parse('form-data; name="a'), isNull);
    });

    test('is null for text after a closing quote', () {
      expect(ContentDisposition.parse('form-data; name="a"b'), isNull);
    });
  });
}
