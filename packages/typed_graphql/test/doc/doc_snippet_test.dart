import 'package:test/test.dart';

import 'doc_snippet.dart';

void main() {
  const snippets = DocSnippets();

  test('a dart fence followed by "It prints:" has an expected output', () {
    final found = snippets.of(
      'a.md',
      '```dart\nmain() {}\n```\n\nIt prints:\n\n```text\nhi\n```\n',
    );
    expect(found, hasLength(1));
    expect(found.single.code, 'main() {}');
    expect(found.single.expectedOutput, 'hi');
    expect(found.single.place, 'a.md:1');
  });

  test('a dart fence with no output fence expects nothing', () {
    final found = snippets.of('a.md', '```dart\nmain() {}\n```\n');
    expect(found.single.expectedOutput, isNull);
  });

  test('a text fence that is not an output is not a program', () {
    expect(
      snippets.of('a.md', 'A signature:\n\n```text\nint f()\n```\n'),
      isEmpty,
    );
  });

  test('a text fence after "It prints:" with no program is an error', () {
    expect(
      () => snippets.of('a.md', 'It prints:\n\n```text\nhi\n```\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('"It prints:" before a fence not tagged text is an error', () {
    expect(
      () => snippets.of(
        'a.md',
        '```dart\nmain() {}\n```\n\nIt prints:\n\n```\nhi\n```\n',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('a tag such as dartpad is an error, not a skipped program', () {
    expect(
      () => snippets.of('a.md', '```dartpad\nmain() {}\n```\n'),
      throwsA(isA<FormatException>()),
    );
  });
}
