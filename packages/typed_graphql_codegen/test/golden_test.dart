@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:typed_graphql_codegen/typed_graphql_codegen.dart';

import 'support/golden_case.dart';

void main() {
  final update = Platform.environment['UPDATE_GOLDENS'] == '1';
  for (final golden in GoldenCase.all()) {
    group(golden.name, () {
      final result = ClientGenerator(
        golden.config,
      ).generate(schema: golden.schema, documents: golden.documents);
      if (update) golden.writeGoldens(result.files);

      test('generates without errors', () {
        expect(result.hasErrors, isFalse, reason: '${result.diagnostics}');
      });

      test('writes the files of the goldens', () {
        expect([
          for (final file in result.files) file.path,
        ], golden.goldens.keys.toList()..sort());
      });

      for (final file in result.files) {
        test('${file.path} equals its golden', () {
          expect(file.text, golden.goldens[file.path]);
        });
      }
    });
  }
}
