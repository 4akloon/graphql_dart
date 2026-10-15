@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('no library outside lib/src/cli imports dart:io', () {
    final offenders = [
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            !entity.path.startsWith('lib/src/cli/') &&
            RegExp(
              r'''^\s*(import|export)\s+['"]dart:io['"]''',
              multiLine: true,
            ).hasMatch(entity.readAsStringSync()))
          entity.path,
    ];
    expect(offenders, isEmpty);
  });
}
