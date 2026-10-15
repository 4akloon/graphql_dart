import 'dart:io';

import 'package:test/test.dart';

import 'golden_case.dart';

/// A temporary Dart package that holds a golden case's generated code, so
/// that the analyzer and the VM check it.
final class GeneratedPackage(
  /// The package's directory.
  final Directory directory,

  /// The case whose goldens and support files it holds.
  final GoldenCase golden,

  /// The workspace root, where `typed_graphql` and `typed_graphql_client` are.
  final String workspace,
) {
  /// Describes the package; [write] creates its files.
  this;

  /// Writes the pubspec, the lints, the goldens and the support files.
  void write() {
    final files = <String, String>{
      'pubspec.yaml':
          '''
name: generated_${golden.name}
publish_to: none
environment:
  sdk: ^3.13.0
dependencies:
${_dependencies()}dev_dependencies:
  lints: ^6.1.0
dependency_overrides:
  typed_graphql:
    path: $workspace/packages/typed_graphql
  typed_graphql_client:
    path: $workspace/packages/typed_graphql_client
''',
      'analysis_options.yaml':
          File(
            '$workspace/analysis_options.yaml',
          ).readAsStringSync().replaceFirst(
            'language:\n',
            'language:\n    strict-casts: true\n',
          ),
      ...golden.goldens,
      ...golden.support,
    };
    for (final entry in files.entries) {
      final file = File('${directory.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
  }

  // The path dependencies, sorted: the two workspace packages and the local
  // packages of the case's `support/packages/`.
  String _dependencies() {
    final paths = <String, String>{
      'typed_graphql': '$workspace/packages/typed_graphql',
      'typed_graphql_client': '$workspace/packages/typed_graphql_client',
      for (final path in golden.support.keys)
        if (path.startsWith('packages/'))
          path.split('/')[1]: 'packages/${path.split('/')[1]}',
    };
    return [
      for (final name in paths.keys.toList()..sort())
        '  $name:\n    path: ${paths[name]}\n',
    ].join();
  }

  /// Runs `dart [arguments]` in [directory] and expects exit code 0.
  static void run(Directory directory, List<String> arguments) {
    final result = Process.runSync(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: directory.path,
    );
    expect(
      result.exitCode,
      0,
      reason:
          'dart ${arguments.join(' ')}:\n${result.stdout}\n${result.stderr}',
    );
  }
}
