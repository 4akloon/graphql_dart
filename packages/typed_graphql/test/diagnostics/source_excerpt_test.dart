import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

void main() {
  const excerpt = SourceExcerpt();

  test('shows the line before, the line with a caret and the line after', () {
    expect(
      excerpt.of(Source('\n\n ~\n'), const SourceLocation(3, 2)),
      'GraphQL request:3:2\n'
      '2 |\n'
      '3 |  ~\n'
      '  |  ^\n'
      '4 |',
    );
  });

  test('ends a line at CRLF and at a lone CR', () {
    expect(
      excerpt.of(Source('a\r\n b\rc'), const SourceLocation(2, 2)),
      'GraphQL request:2:2\n'
      '1 | a\n'
      '2 |  b\n'
      '  |  ^\n'
      '3 | c',
    );
  });

  test('leaves out the lines a document does not have', () {
    expect(
      excerpt.of(Source('{', name: 'a.graphql'), const SourceLocation(1, 2)),
      'a.graphql:1:2\n'
      '1 | {\n'
      '  |  ^',
    );
  });

  test('pads every prefix to the widest line number', () {
    expect(
      excerpt.of(Source('${'\n' * 8}*\n'), const SourceLocation(9, 1)),
      'GraphQL request:9:1\n'
      ' 8 |\n'
      ' 9 | *\n'
      '   | ^\n'
      '10 |',
    );
  });

  test('cuts a line longer than 120 units into 80-unit pieces', () {
    final line = '${'a' * 80}${'b' * 80}${'c' * 10}';
    expect(
      excerpt.of(Source(line), const SourceLocation(1, 85)),
      'GraphQL request:1:85\n'
      '1 | ${'a' * 80}\n'
      '  | ${'b' * 80}\n'
      '  |     ^\n'
      '  | ${'c' * 10}',
    );
  });

  test('a caret after the last piece of a long line shows no piece after', () {
    final line = 'a' * 160;
    expect(
      excerpt.of(Source(line), const SourceLocation(1, 161)),
      'GraphQL request:1:161\n'
      '1 | ${'a' * 80}\n'
      '  | ${'a' * 80}\n'
      '  | ^',
    );
  });

  test('a span shows its start', () {
    final source = Source('{ a }\n{');
    final span = SourceSpan(source, 7, 7);
    expect(span.excerpt, excerpt.of(source, const SourceLocation(2, 2)));
  });
}
