@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'layer_rule.dart';

void main() {
  const rule = LayerRule();

  group('LayerRule', () {
    test('allows the same layer, lower layers and pure Dart', () {
      expect(
        rule.check(
          'lib/src/protocol/graphql_error.dart',
          "import 'dart:convert';\n"
              "import 'package:meta/meta.dart';\n"
              "import '../diagnostics/source_location.dart';\n"
              "import 'json_value.dart';\n",
        ),
        isEmpty,
      );
    });

    test('rejects an import of a higher layer', () {
      expect(
        rule.check(
          'lib/src/diagnostics/diagnostic.dart',
          "import '../protocol/json_value.dart';\n",
        ),
        [
          'diagnostics/diagnostic.dart imports ../protocol/json_value.dart: '
              'diagnostics must not depend on protocol',
        ],
      );
    });

    test('rejects an export of a higher layer', () {
      expect(
        rule.check(
          'lib/src/language/ast.dart',
          'export "../schema/schema.dart";\n',
        ),
        hasLength(1),
      );
    });

    test('rejects dart:io and packages other than meta', () {
      expect(
        rule.check(
          'lib/src/protocol/a.dart',
          "import 'dart:io';\nimport 'package:collection/collection.dart';\n",
        ),
        hasLength(2),
      );
    });

    test('rejects the barrel and folders that are not layers', () {
      expect(
        rule.check(
          'lib/src/protocol/a.dart',
          "import '../../typed_graphql.dart';\n",
        ),
        hasLength(1),
      );
      expect(rule.check('lib/src/misc/a.dart', ''), hasLength(1));
      expect(rule.check('lib/src/a.dart', ''), hasLength(1));
    });

    test('reads Windows paths', () {
      expect(
        rule.check(
          r'C:\work\packages\typed_graphql\lib\src\diagnostics\a.dart',
          "import '../schema/schema.dart';\n",
        ),
        [
          'diagnostics/a.dart imports ../schema/schema.dart: '
              'diagnostics must not depend on schema',
        ],
      );
    });
  });

  test('lib/src follows the layer rule', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      startsWith('name: typed_graphql\n'),
      reason: 'run from packages/typed_graphql',
    );
    final src = Directory('lib/src');
    final files = src.existsSync()
        ? src.listSync(recursive: true).whereType<File>()
        : const <File>[];
    final violations = [
      for (final file in files)
        if (file.path.endsWith('.dart'))
          ...rule.check(file.path, file.readAsStringSync()),
    ];
    expect(violations, isEmpty);
  });
}
