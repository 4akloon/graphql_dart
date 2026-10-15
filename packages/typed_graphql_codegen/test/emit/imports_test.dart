import 'package:test/test.dart';
import 'package:typed_graphql_codegen/src/emit/dart_writer.dart';
import 'package:typed_graphql_codegen/src/emit/imports.dart';

void main() {
  test('write orders the groups and sorts each', () {
    final Imports imports = Imports()
      ..relative('schema.graphql.dart')
      ..package(
        'package:typed_graphql_client/typed_graphql_client.dart',
        prefix: 'client',
      )
      ..package('package:typed_graphql/typed_graphql.dart', prefix: 'graphql')
      ..package('dart:convert')
      ..relative('codecs.dart', prefix: 'scalar_0')
      ..package('dart:async');
    final DartWriter writer = DartWriter();
    imports.write(writer);
    expect(
      writer.text,
      "import 'dart:async';\n"
      "import 'dart:convert';\n"
      '\n'
      "import 'package:typed_graphql/typed_graphql.dart' as graphql;\n"
      "import 'package:typed_graphql_client/typed_graphql_client.dart' "
      'as client;\n'
      '\n'
      "import 'codecs.dart' as scalar_0;\n"
      "import 'schema.graphql.dart';\n",
    );
  });

  test('write omits empty groups and their blank lines', () {
    final Imports imports = Imports()..relative('a.dart');
    final DartWriter writer = DartWriter();
    imports.write(writer);
    expect(writer.text, "import 'a.dart';\n");
  });

  test('prefixFor counts from zero and repeats a known uri', () {
    final Imports imports = Imports();
    expect(
      <String>[
        imports.prefixFor('package:money/money.dart'),
        imports.prefixFor('dart:typed_data'),
        imports.prefixFor('package:money/money.dart'),
      ],
      <String>['scalar_0', 'scalar_1', 'scalar_0'],
    );
  });

  test('prefixFor records the import once', () {
    final Imports imports = Imports();
    imports.prefixFor('package:money/money.dart');
    imports.prefixFor('package:money/money.dart');
    final DartWriter writer = DartWriter();
    imports.write(writer);
    expect(writer.text, "import 'package:money/money.dart' as scalar_0;\n");
  });

  test('one uri with two prefixes is written twice', () {
    final Imports imports = Imports()
      ..package('package:a/a.dart', prefix: 'x')
      ..package('package:a/a.dart', prefix: 'y');
    final DartWriter writer = DartWriter();
    imports.write(writer);
    expect(
      writer.text,
      "import 'package:a/a.dart' as x;\nimport 'package:a/a.dart' as y;\n",
    );
  });
}
