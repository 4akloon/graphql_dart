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

  test('no library the barrel reaches imports dart:io', () {
    final pending = ['lib/typed_graphql_codegen.dart'];
    final seen = <String>{};
    final offenders = <String>[];
    final directive = RegExp(
      r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    while (pending.isNotEmpty) {
      final path = pending.removeLast();
      if (!seen.add(path)) continue;
      for (final match in directive.allMatches(
        File(path).readAsStringSync(),
      )) {
        final target = match.group(1)!;
        if (target == 'dart:io') offenders.add(path);
        if (target.startsWith('package:') || target.startsWith('dart:')) {
          continue;
        }
        pending.add(
          Uri.file(path).resolve(target).toFilePath(),
        );
      }
    }
    expect(offenders, isEmpty);
  });
}
