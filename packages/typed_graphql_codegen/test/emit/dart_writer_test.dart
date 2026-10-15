import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';

void main() {
  test('line indents and leaves empty lines bare', () {
    final DartWriter writer = DartWriter();
    writer.indented(() {
      writer.line('a');
      writer.line();
    });
    writer.line('b');
    expect(writer.text, '  a\n\nb\n');
  });

  test('block nests its body', () {
    final DartWriter writer = DartWriter();
    writer.block('class A', () {
      writer.block('void f()', () => writer.line('x();'));
    });
    expect(writer.text, 'class A {\n  void f() {\n    x();\n  }\n}\n');
  });

  test('doc writes one comment line per line', () {
    final DartWriter writer = DartWriter();
    writer.doc('First.\n\nSecond.');
    expect(writer.text, '/// First.\n///\n/// Second.\n');
  });

  test('doc gives an opening bare fence the text language', () {
    final DartWriter writer = DartWriter();
    writer.doc('A.\n```\ncode\n```\nB.\n```\nmore\n```');
    expect(
      writer.text,
      '/// A.\n/// ```text\n/// code\n/// ```\n/// B.\n'
      '/// ```text\n/// more\n/// ```\n',
    );
  });

  test('doc keeps a fence that already has a language', () {
    final DartWriter writer = DartWriter();
    writer.doc('```dart\nx\n```');
    expect(writer.text, '/// ```dart\n/// x\n/// ```\n');
  });

  test('items stays on one line at exactly 80 columns', () {
    final DartWriter writer = DartWriter();
    final String filler = 'a' * (80 - 'const X({'.length - '});'.length);
    writer.items('const X({', <String>[filler], '});');
    expect(writer.text, 'const X({$filler});\n');
    expect(writer.text.trimRight().length, 80);
  });

  test('items splits at 81 columns', () {
    final DartWriter writer = DartWriter();
    final String filler = 'a' * (81 - 'const X({'.length - '});'.length);
    writer.items('const X({', <String>[filler], '});');
    expect(writer.text, 'const X({\n  $filler,\n});\n');
  });

  test('items counts the indentation', () {
    final DartWriter writer = DartWriter();
    final String filler = 'a' * (79 - 'f('.length - ')'.length);
    writer.indented(() => writer.items('f(', <String>[filler], ')'));
    expect(writer.text, '  f(\n    $filler,\n  )\n');
  });

  test('items joins several items with a comma', () {
    final DartWriter writer = DartWriter();
    writer.items('f(', <String>['a', 'b'], ');');
    expect(writer.text, 'f(a, b);\n');
  });

  test('text of an empty writer is empty', () {
    expect(DartWriter().text, '');
  });
}
