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

  test('assign stays on one line when it fits', () {
    final DartWriter writer = DartWriter();
    writer.assign('final x', 'f(1)');
    expect(writer.text, 'final x = f(1);\n');
  });

  test('assign breaks after the equals sign when that fits', () {
    final DartWriter writer = DartWriter();
    final String call = 'f(${'a' * 70})';
    writer.assign('final x', call);
    expect(writer.text, 'final x =\n    $call;\n');
  });

  test('arrow breaks a long call into its arguments', () {
    final DartWriter writer = DartWriter();
    final String inner = 'g(${'a' * 70})';
    writer.arrow('int get x', 'f($inner)');
    expect(writer.text, 'int get x => f(\n  $inner,\n);\n');
  });

  test('arrowJoined puts one operand per line when it is too long', () {
    final DartWriter writer = DartWriter();
    final String operand = 'a' * 40;
    writer.arrowJoined('bool get x', <String>[operand, operand], '&&');
    expect(
      writer.text,
      'bool get x =>\n    $operand &&\n    $operand;\n',
    );
  });

  test('arrowJoined joins the operands on one line when they fit', () {
    final DartWriter writer = DartWriter();
    writer.arrowJoined('bool get x', <String>['a', 'b'], '&&');
    expect(writer.text, 'bool get x => a && b;\n');
  });

  test('arrow keeps a call without arguments whole when it is too long', () {
    final DartWriter writer = DartWriter();
    final String codec = '${'A' * 80}()';
    writer.arrow('int get x', 'f($codec)');
    expect(writer.text, 'int get x => f(\n  $codec,\n);\n');
  });

  test('doc forgets an unclosed fence of the previous comment', () {
    final DartWriter writer = DartWriter();
    writer
      ..doc('```\ncode')
      ..doc('```\nmore\n```');
    expect(
      writer.text,
      '/// ```text\n/// code\n/// ```text\n/// more\n/// ```\n',
    );
  });

  test('doc leaves no trailing whitespace and drops carriage returns', () {
    final DartWriter writer = DartWriter();
    writer.doc('a  \r\n   \nb');
    expect(writer.text, '/// a\n///\n/// b\n');
  });
}
