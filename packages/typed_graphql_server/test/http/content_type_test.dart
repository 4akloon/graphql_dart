import 'package:test/test.dart';
import 'package:typed_graphql_server/src/http/content_type.dart';

void main() {
  test('reads the media type lower-cased', () {
    expect(
      ContentType.parse('Application/JSON')!.mediaType,
      'application/json',
    );
  });

  test('has no parameters when none is given', () {
    expect(ContentType.parse('application/json')!.parameters, isEmpty);
  });

  test('reads parameters with lower-cased names', () {
    final type = ContentType.parse('application/json; Charset=UTF-8')!;
    expect(type.parameters, {'charset': 'UTF-8'});
    expect(type.charset, 'utf-8');
  });

  test('has no charset without the parameter', () {
    expect(ContentType.parse('application/json')!.charset, isNull);
  });

  test('unquotes a quoted value', () {
    final type = ContentType.parse('multipart/form-data; boundary="a b"')!;
    expect(type.parameters['boundary'], 'a b');
  });

  test('resolves backslash escapes in a quoted value', () {
    final type = ContentType.parse(r'a/b; x="q\"uote\\"')!;
    expect(type.parameters['x'], r'q"uote\');
  });

  test('keeps a semicolon inside quotes', () {
    final type = ContentType.parse('a/b; x="1;2"; y=3')!;
    expect(type.parameters, {'x': '1;2', 'y': '3'});
  });

  test('ignores an empty segment', () {
    expect(ContentType.parse('a/b;')!.parameters, isEmpty);
  });

  test('is null for a missing header', () {
    expect(ContentType.parse(null), isNull);
  });

  test('is null without a slash or with an empty part', () {
    for (final text in [
      'json',
      '',
      '/json',
      'application/',
      'a/b/c',
      'a b/c',
    ]) {
      expect(ContentType.parse(text), isNull, reason: text);
    }
  });

  test('is null for a parameter without a value or a name', () {
    expect(ContentType.parse('a/b; charset'), isNull);
    expect(ContentType.parse('a/b; =x'), isNull);
  });

  test('is null for an unterminated quote', () {
    expect(ContentType.parse('a/b; x="open'), isNull);
  });

  test('is null for text after the closing quote', () {
    expect(ContentType.parse('a/b; x="v"w'), isNull);
  });

  test('keeps the parameters unmodifiable', () {
    expect(
      () => ContentType.parse('a/b; x=1')!.parameters['y'] = '2',
      throwsUnsupportedError,
    );
  });
}
