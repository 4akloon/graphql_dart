@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Every exported public class is in the dartdoc category of the package, and
/// `dartdoc_options.yaml` declares it with a guide (R11.2).
void main() {
  final barrel = File('lib/typed_graphql_shelf.dart').readAsStringSync();
  final exported = [
    for (final match in RegExp("export '([^']+)';").allMatches(barrel))
      match[1]!,
  ];
  final options = File('dartdoc_options.yaml').readAsStringSync();

  test('the category is declared with a guide that exists', () {
    expect(options, contains('shelf:\n      markdown: doc/shelf.md'));
    expect(File('doc/shelf.md').existsSync(), isTrue);
  });

  for (final path in exported) {
    test('$path tags each public class with the category', () {
      final source = File('lib/$path').readAsStringSync();
      final classes = RegExp(
        '^(?:final |base |abstract |sealed )*class [A-Z]',
        multiLine: true,
      ).allMatches(source);
      final tags = '{@category shelf}'.allMatches(source);
      expect(tags, hasLength(classes.length));
    });
  }
}
