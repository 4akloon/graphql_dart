@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'import_rule.dart';

void main() {
  const rule = ImportRule();

  group('ImportRule', () {
    test('allows pure Dart, meta, the core barrel and relative paths', () {
      expect(
        rule.check(
          'lib/src/builder/a.dart',
          "import 'dart:async';\n"
              "import 'dart:core' as core;\n"
              "import 'package:meta/meta.dart';\n"
              "import 'package:typed_graphql/typed_graphql.dart';\n"
              "import '../execution/b.dart';\n",
        ),
        isEmpty,
      );
    });

    test('rejects dart:io', () {
      expect(
        rule.check('lib/src/builder/a.dart', "import 'dart:io';\n"),
        hasLength(1),
      );
    });

    test('rejects the core src folder', () {
      expect(
        rule.check(
          'lib/src/builder/a.dart',
          "import 'package:typed_graphql/src/schema/schema.dart';\n",
        ),
        hasLength(1),
      );
    });

    test('rejects shelf', () {
      expect(
        rule.check(
          'lib/src/builder/a.dart',
          "import 'package:shelf/shelf.dart';\n",
        ),
        hasLength(1),
      );
    });
  });

  test('lib follows the import rule', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      startsWith('name: typed_graphql_server\n'),
      reason: 'run from packages/typed_graphql_server',
    );
    final violations = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          ...rule.check(file.path, file.readAsStringSync()),
    ];
    expect(violations, isEmpty);
  });
}
