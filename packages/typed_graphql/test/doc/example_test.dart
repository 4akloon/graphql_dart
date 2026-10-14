@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

import 'doc_snippet.dart';

/// The package README shows `example/example.dart` as its quick tour: the
/// two must not drift apart (R11.2).
void main() {
  test('the first program in the README is example/example.dart', () {
    final readme = File('README.md').readAsStringSync();
    final first = const DocSnippets().of('README.md', readme).first;
    final example = File('example/example.dart').readAsStringSync();
    expect(first.code.trimRight(), example.trimRight());
  });
}
