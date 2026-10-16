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
          'lib/src/link/a.dart',
          "import 'dart:async';\n"
              "import 'dart:typed_data';\n"
              "import 'package:meta/meta.dart';\n"
              "import 'package:typed_graphql/typed_graphql.dart';\n"
              "import '../client/b.dart';\n",
        ),
        isEmpty,
      );
    });

    test('rejects dart:io', () {
      expect(
        rule.check('lib/src/link/a.dart', "import 'dart:io';\n"),
        hasLength(1),
      );
    });

    test('rejects a web-only library', () {
      expect(
        rule.check('lib/src/link/a.dart', "import 'dart:js_interop';\n"),
        hasLength(1),
      );
    });

    test('rejects the core src folder', () {
      expect(
        rule.check(
          'lib/src/link/a.dart',
          "import 'package:typed_graphql/src/protocol/json_value.dart';\n",
        ),
        hasLength(1),
      );
    });

    test('rejects an export of dart:io', () {
      expect(
        rule.check('lib/src/link/a.dart', "export 'dart:io';\n"),
        hasLength(1),
      );
    });

    test('rejects any URI of a conditional import', () {
      expect(
        rule.check(
          'lib/src/link/a.dart',
          "import 'a_stub.dart'\n"
              "    if (dart.library.io) 'dart:io'\n"
              "    if (dart.library.js_interop) 'a_web.dart';\n",
        ),
        hasLength(1),
      );
    });

    test('rejects a relative path that leaves lib', () {
      expect(
        rule.check(
          'lib/src/link/a.dart',
          "import '../../../test/support/b.dart';\n",
        ),
        hasLength(1),
      );
    });

    test('allows a relative path that stays in lib', () {
      expect(
        rule.check(
          'lib/src/link/a.dart',
          "import '../../typed_graphql_client.dart';\n",
        ),
        isEmpty,
      );
    });

    test('rejects a meta library other than meta.dart', () {
      expect(
        rule.check(
          'lib/src/link/a.dart',
          "import 'package:meta/meta_meta.dart';\n",
        ),
        hasLength(1),
      );
    });

    test('rejects another package', () {
      expect(
        rule.check(
          'lib/src/link/a.dart',
          "import 'package:web_socket_channel/web_socket_channel.dart';\n",
        ),
        hasLength(1),
      );
    });
  });

  test('lib follows the import rule', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      startsWith('name: typed_graphql_client\n'),
      reason: 'run from packages/typed_graphql_client',
    );
    final violations = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          ...rule.check(file.path, file.readAsStringSync()),
    ];
    expect(violations, isEmpty);
  });
}
