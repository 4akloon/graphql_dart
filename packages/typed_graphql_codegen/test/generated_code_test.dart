@TestOn('vm')
@Tags(['analysis'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/generated_package.dart';
import 'support/golden_case.dart';

void main() {
  // Under `dart test --compiler exe` the running executable is the compiled
  // test, not the SDK's `dart`, so the commands below cannot run; the JIT
  // job runs this suite.
  final String tool = Platform.resolvedExecutable.split(RegExp(r'[/\\]')).last;
  final String? skip = tool == 'dart' || tool == 'dart.exe'
      ? null
      : 'the test is compiled: run it with the dart tool (JIT)';
  final workspace = Directory.current.parent.parent.path;
  for (final golden in GoldenCase.all()) {
    group(golden.name, () {
      // Assigned by setUp, which runs before every test of the group.
      late Directory package;

      setUp(() {
        package = Directory.systemTemp.createTempSync('generated_');
        GeneratedPackage(package, golden, workspace).write();
      });

      tearDown(() => package.deleteSync(recursive: true));

      test(
        'passes the analyzer and round trips its sample values',
        skip: skip,
        () {
          GeneratedPackage.run(package, ['pub', 'get', '--offline']);
          GeneratedPackage.run(package, ['analyze', '--fatal-infos']);
          if (golden.support.containsKey('bin/round_trip.dart')) {
            GeneratedPackage.run(package, ['run', 'bin/round_trip.dart']);
          }
        },
      );
    });
  }
}
