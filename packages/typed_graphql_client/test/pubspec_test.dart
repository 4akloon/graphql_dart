@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('requires Dart 3.13 (R0.5)', () {
    expect(pubspec, contains('sdk: ^3.13.0'));
  });

  test('resolves in the workspace', () {
    expect(pubspec, contains('resolution: workspace'));
  });
}
