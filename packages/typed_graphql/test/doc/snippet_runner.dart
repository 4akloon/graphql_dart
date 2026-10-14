import 'dart:convert';
import 'dart:io';

import 'doc_snippet.dart';

/// What running a snippet gave.
final class SnippetRun(
  /// The exit code; 0 when the program ran to its end.
  final int exitCode,

  /// Standard output, with `\n` line ends and no trailing white space.
  final String output,

  /// Standard error: the compile errors, or the uncaught exception.
  final String errors,
) {
  /// Creates a result.
  this;
}

/// Runs a [DocSnippet] as its own program, against this workspace's
/// packages.
///
/// It starts the `dart` executable that runs the tests, so it cannot work
/// in a test compiled with `--compiler exe`: [isAvailable] tells.
final class SnippetRunner(
  /// The `package_config.json` the program resolves `package:` imports with.
  final String packageConfig,

  /// A folder to write the programs to; the caller deletes it.
  final Directory directory, {

  /// How long a program may run before it is killed; a guide's program
  /// takes about a second.
  final Duration timeLimit = const Duration(seconds: 60),
}) {
  /// Creates a runner.
  this;

  /// Whether the running test is the `dart` tool itself, not an executable
  /// compiled from the test.
  ///
  /// A test compiled with `--compiler exe` runs on `dartaotruntime`, which
  /// cannot run a source file, so the name must be exactly `dart`.
  static bool get isAvailable => const [
    'dart',
    'dart.exe',
  ].contains(Platform.resolvedExecutable.split(RegExp(r'[/\\]')).last);

  /// The heap a program may use, in megabytes: a runaway program fails
  /// by itself instead of taking the machine's memory.
  static const int heapLimit = 512;

  /// Writes [snippet] to `<name>.dart` and runs it, alone, within
  /// [timeLimit] and [heapLimit]. A program that runs too long is killed
  /// and gives exit code -1.
  Future<SnippetRun> run(DocSnippet snippet, String name) async {
    final program = File('${directory.path}/$name.dart')
      ..writeAsStringSync('${snippet.code}\n');
    final process = await Process.start(Platform.resolvedExecutable, [
      '--old-gen-heap-size=$heapLimit',
      '--packages=$packageConfig',
      program.path,
    ]);
    final output = utf8.decodeStream(process.stdout);
    final errors = utf8.decodeStream(process.stderr);
    final exitCode = await process.exitCode.timeout(
      timeLimit,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    return SnippetRun(
      exitCode,
      _normalized(await output),
      _normalized(
        exitCode == -1 ? 'timed out after $timeLimit' : await errors,
      ),
    );
  }

  /// The places of the [snippets] that `dart format` would change, found
  /// by one `dart format` run over all of them.
  Future<List<String>> unformattedPlaces(List<DocSnippet> snippets) async {
    final folder = Directory('${directory.path}/format')..createSync();
    for (final (index, snippet) in snippets.indexed) {
      File('${folder.path}/s$index.dart')
          .writeAsStringSync('${snippet.code}\n');
    }
    final result = await Process.run(Platform.resolvedExecutable, [
      'format',
      '--output=none',
      folder.path,
    ]).timeout(timeLimit);
    return [
      for (final match in RegExp(
        r'^Changed .*s(\d+)\.dart$',
        multiLine: true,
      ).allMatches('${result.stdout}'.replaceAll('\r\n', '\n')))
        snippets[int.parse(match[1]!)].place,
    ];
  }

  /// [text] with `\n` line ends and without trailing white space, so the
  /// comparison does not depend on the platform.
  static String _normalized(String text) =>
      text.replaceAll('\r\n', '\n').trimRight();
}
