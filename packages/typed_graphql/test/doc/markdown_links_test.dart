@TestOn('vm')
library;

import 'package:test/test.dart';

import 'markdown_links.dart';

void main() {
  const links = MarkdownLinks();

  test('finds relative links and their lines, and skips web links', () {
    final found = links.relativeIn(
      'See [a](doc/a.md) and [b](https://x.dev/b).\n[c](#top)\n',
    );
    expect(found.map((link) => link.target), ['doc/a.md', '#top']);
    expect(found.map((link) => link.line), [1, 2]);
  });

  test('leaves out links inside fenced code', () {
    expect(links.relativeIn('```text\n[a](b.md)\n```\n'), isEmpty);
  });

  test('turns headings into GitHub anchors', () {
    expect(
      links.anchorsIn('# Scalars & Codecs\n\n## What it does, 1\n'),
      {'scalars--codecs', 'what-it-does-1'},
    );
  });

  test('numbers the anchors of a repeated heading', () {
    expect(links.anchorsIn('## Same\n\n## Same\n'), {'same', 'same-1'});
  });

  test('a comment line in a fence is not a heading', () {
    expect(links.anchorsIn('```text\n# not a heading\n```\n'), isEmpty);
  });

  test('leaves out links inside a tilde fence', () {
    expect(
      links.relativeIn('~~~text\n[a](b.md)\n~~~\n[c](d.md)\n'),
      hasLength(1),
    );
  });

  test('a four-backtick fence holds a three-backtick line', () {
    expect(links.relativeIn('````md\n```\n[a](b.md)\n````\n'), isEmpty);
  });

  test('leaves out links inside an indented fence', () {
    expect(links.relativeIn('  ```text\n  [a](b.md)\n  ```\n'), isEmpty);
  });

  test('keeps line numbers across a fence', () {
    expect(links.relativeIn('```text\nx\n```\n[a](b.md)').single.line, 4);
  });

  test('a link to a directory with an anchor fails with a clear message', () {
    expect(
      () => links.readTarget('doc'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('is not a file'),
        ),
      ),
    );
  });
}
