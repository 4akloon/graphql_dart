import 'package:test/test.dart';

import 'markdown_fence.dart';

void main() {
  const fences = MarkdownFences();

  test('reads the tag, the body and the line of each fence', () {
    final found = fences.of('Intro.\n\n```dart\nvar a = 1;\nvar b = 2;\n```\n');
    expect(found, hasLength(1));
    expect(found.single.info, 'dart');
    expect(found.single.body, 'var a = 1;\nvar b = 2;');
    expect(found.single.line, 3);
  });

  test('keeps the prose between two fences as the preceding text', () {
    final found = fences.of(
      '```dart\na\n```\n\nIt prints:\n\n```text\nb\n```\n',
    );
    expect(found.last.precedingText, 'It prints:');
  });

  test('a fence with no tag has an empty info', () {
    expect(fences.of('```\nx\n```').single.info, '');
  });

  test('ignores a line indented four spaces, which is code', () {
    expect(fences.of('    ```dart\n    x\n    ```'), isEmpty);
  });

  test('reads a tilde fence and an indented one', () {
    expect(fences.of('~~~dart\nx\n~~~').single.info, 'dart');
    expect(fences.of('  ```dart\n  x\n  ```').single.body, '  x');
  });

  test('a longer opening is closed only by an equal or longer line', () {
    expect(fences.of('````md\n```\ny\n````').single.body, '```\ny');
  });

  test('an unclosed fence is a FormatException', () {
    expect(
      () => fences.of('```dart\nvar a = 1;\n'),
      throwsA(isA<FormatException>()),
    );
  });
}
