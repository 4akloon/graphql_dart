@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'public_type.dart';

/// Every exported type is in the dartdoc category of its folder, and
/// `dartdoc_options.yaml` declares those categories, each with a guide
/// (R11.2).
void main() {
  final barrel = File('lib/typed_graphql.dart').readAsStringSync();
  final exported = [
    for (final match in RegExp("export '([^']+)';").allMatches(barrel))
      match[1]!,
  ];
  final options = File('dartdoc_options.yaml').readAsStringSync();
  final declared = [
    for (final match in RegExp(
      r'^ {4}([a-z-]+):$',
      multiLine: true,
    ).allMatches(options))
      match[1]!,
  ];

  /// The category of the types in the library file [path], from `lib/`.
  String categoryOf(String path) => switch (path.split('/')) {
    ['src', 'schema', 'scalars', ...] => 'scalars',
    ['src', 'schema', 'introspection', ...] => 'introspection',
    ['src', final layer, ...] => layer,
    _ => throw ArgumentError.value(path, 'path', 'is not under lib/src'),
  };

  test('the library page is in the getting-started category', () {
    expect(barrel, contains('/// {@category getting-started}\nlibrary;'));
  });

  test('every category used is declared, and every one declared is used', () {
    final used = {'getting-started', ...exported.map(categoryOf)};
    expect(declared.toSet(), used);
  });

  test('every declared category has its guide', () {
    for (final match in RegExp(r'markdown: (doc/\S+)').allMatches(options)) {
      expect(File(match[1]!).existsSync(), isTrue, reason: match[1]);
    }
    expect(
      RegExp('markdown: doc').allMatches(options),
      hasLength(declared.length),
    );
  });

  test('the category order lists every declared category once', () {
    final order = [
      for (final match in RegExp(
        r'^ {4}- ([a-z-]+)$',
        multiLine: true,
      ).allMatches(options))
        match[1]!,
    ];
    expect(order, declared);
  });

  group('exported types', () {
    for (final path in exported) {
      test(path, () {
        final tag = '{@category ${categoryOf(path)}}';
        final source = File('lib/$path').readAsStringSync();
        final untagged = [
          for (final type in const PublicTypes().declaredIn(source))
            if (type.countOf(tag) != 1) type.name,
        ];
        expect(
          untagged,
          isEmpty,
          reason: 'give each exactly one $tag in its doc comment',
        );
      });
    }
  });
}
