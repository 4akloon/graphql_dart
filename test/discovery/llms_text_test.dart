@TestOn('vm')
library;

import 'package:test/test.dart';

import 'llms_text.dart';

void main() {
  const text =
      '# name\n'
      '\n'
      '> One line\n'
      '> and two.\n'
      '\n'
      '## Docs\n'
      '\n'
      '- [A](https://x.dev/a.md): the a\n'
      '- [B](https://x.dev/b.md)\n'
      '\n'
      '## More\n'
      '\n'
      '- [C](https://x.dev/c.md): the c\n';

  test('reads the title', () {
    expect(LlmsText(text).titles, ['name']);
  });

  test('joins the lines of a summary', () {
    expect(LlmsText(text).summaries, ['One line and two.']);
  });

  test('reads the sections in order', () {
    expect(LlmsText(text).sections, ['Docs', 'More']);
  });

  test('reads the entries of one section only', () {
    final entries = LlmsText(text).entriesOf('Docs');
    expect(entries.map((entry) => entry.url), [
      'https://x.dev/a.md',
      'https://x.dev/b.md',
    ]);
  });

  test('an entry without a colon has an empty description', () {
    expect(LlmsText(text).entriesOf('Docs').last.description, isEmpty);
  });

  test('a missing section has no entries', () {
    expect(LlmsText(text).entriesOf('Optional'), isEmpty);
  });

  test('reads a file written with CRLF line endings', () {
    final windows = LlmsText(text.replaceAll('\n', '\r\n'));
    expect(windows.entriesOf('More').single.description, 'the c');
  });
}
