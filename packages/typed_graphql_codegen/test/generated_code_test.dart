@TestOn('vm')
@Tags(['analysis'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/generated_package.dart';
import 'support/golden_case.dart';

void main() {
  final workspace = Directory.current.parent.parent.path;
  for (final golden in GoldenCase.all()) {
    group(golden.name, () {
      late Directory package;

      setUp(() {
        package = Directory.systemTemp.createTempSync('generated_');
        GeneratedPackage(package, golden, workspace).write();
      });

      tearDown(() => package.deleteSync(recursive: true));

      test('passes the analyzer and round trips its sample values', () {
        GeneratedPackage.run(package, ['pub', 'get', '--offline']);
        GeneratedPackage.run(package, ['analyze', '--fatal-infos']);
        if (golden.support.containsKey('bin/round_trip.dart')) {
          GeneratedPackage.run(package, ['run', 'bin/round_trip.dart']);
        }
      });
    });
  }
}
