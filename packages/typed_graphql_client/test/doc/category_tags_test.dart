@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import '../../../typed_graphql/test/doc/public_type.dart';

/// Every exported type is in the `operations` dartdoc category, which
/// `dartdoc_options.yaml` declares with its guide (R11.2).
void main() {
  final barrel = File('lib/typed_graphql_client.dart').readAsStringSync();
  final exported = [
    for (final match in RegExp("export '([^']+)';").allMatches(barrel))
      match[1]!,
  ];
  final options = File('dartdoc_options.yaml').readAsStringSync();

  test('the only category declared is operations', () {
    final declared = [
      for (final match in RegExp(
        r'^ {4}([a-z-]+):$',
        multiLine: true,
      ).allMatches(options))
        match[1]!,
    ];
    expect(declared, ['operations']);
  });

  test('the category has its guide', () {
    expect(options, contains('markdown: doc/operations.md'));
    expect(File('doc/operations.md').existsSync(), isTrue);
  });

  group('exported types', () {
    for (final path in exported) {
      test(path, () {
        final source = File('lib/$path').readAsStringSync();
        final untagged = [
          for (final type in const PublicTypes().declaredIn(source))
            if (type.countOf('{@category operations}') != 1) type.name,
        ];
        expect(
          untagged,
          isEmpty,
          reason: 'give each exactly one {@category operations} in its doc',
        );
      });
    }
  });
}
