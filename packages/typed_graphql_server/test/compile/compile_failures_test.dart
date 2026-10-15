@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Compiles fixtures with the front end, as a user's build would.
class FixtureCompiler {
  /// Creates the compiler.
  const FixtureCompiler();

  /// Compiles one fixture, checks that it passed or failed as expected and
  /// returns the compiler output.
  Future<String> compile(String name, {required bool isExpected}) async {
    final directory = Directory('.dart_tool/compile_fixtures')
      ..createSync(recursive: true);
    final source = File('test/compile/fixtures/$name.dart.txt');
    final target = File('${directory.path}/$name.dart')
      ..writeAsStringSync(source.readAsStringSync());
    final result = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'kernel',
      target.path,
      '-o',
      '${directory.path}/$name.dill',
    ]).timeout(const Duration(seconds: 150));
    final output = '${result.stdout}${result.stderr}';
    expect(result.exitCode == 0, isExpected, reason: output);
    return output;
  }
}

void main() {
  const compiler = FixtureCompiler();
  const timeout = Timeout(Duration(minutes: 3));

  test('a correct program compiles', () async {
    await compiler.compile('ok', isExpected: true);
  }, timeout: timeout);

  const failing = {
    'nullable_for_non_null': "can't be returned from",
    'wrong_result_type': "can't be returned from",
    'unrelated_union_member':
        "'ObjectTypeDef<Rock>' can't be assigned to a variable of type "
        "'ObjectTypeDef<Animal>'",
    'wrong_argument_read':
        "'Arg<int>' can't be assigned to the parameter type 'Arg<String>'",
  };
  failing.forEach((name, text) {
    test('$name does not compile', () async {
      final output = await compiler.compile(name, isExpected: false);
      expect(output, contains(text));
    }, timeout: timeout);
  });
}
