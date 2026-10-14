import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'doc_snippet.dart';

/// What running a snippet gave.
final class SnippetRun(
  /// The exit code; 0 when the program ran to its end.
  final int exitCode,

  /// Standard output, with `\n` line ends and no trailing white space.
  final String output,

  /// Standard error: the compile errors, or the uncaught exception.
  final String errors, {

  /// Whether the program was killed for running past the time limit.
  final bool hasTimedOut = false,
}) {
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

  /// The bytes a program may print to each of its streams before it is
  /// killed, so an endless loop of `print` cannot fill the memory.
  static const int outputLimit = 1024 * 1024;

  /// Writes [snippet] to `<name>.dart` and runs it, alone, within
  /// [timeLimit], [heapLimit] and [outputLimit]. A program that runs too
  /// long is killed and has [SnippetRun.hasTimedOut]; one that prints too
  /// much is killed and reports it in [SnippetRun.errors].
  Future<SnippetRun> run(DocSnippet snippet, String name) async {
    final program = File('${directory.path}/$name.dart')
      ..writeAsStringSync('${snippet.code}\n');
    final result = await _start([
      '--old-gen-heap-size=$heapLimit',
      '--packages=$packageConfig',
      program.path,
    ]);
    return SnippetRun(
      result.exitCode,
      _normalized(result.output),
      _normalized(result.errors),
      hasTimedOut: result.hasTimedOut,
    );
  }

  /// The places of the [snippets] that `dart format` would change, found
  /// by one `dart format` run over all of them.
  Future<List<String>> unformattedPlaces(List<DocSnippet> snippets) async {
    final folder = Directory('${directory.path}/format')..createSync();
    for (final (index, snippet) in snippets.indexed) {
      File(
        '${folder.path}/s$index.dart',
      ).writeAsStringSync('${snippet.code}\n');
    }
    final result = await _start(['format', '--output=none', folder.path]);
    if (result.hasTimedOut) {
      throw StateError('dart format timed out after $timeLimit');
    }
    return [
      for (final match in RegExp(
        r'^Changed .*s(\d+)\.dart$',
        multiLine: true,
      ).allMatches(result.output.replaceAll('\r\n', '\n')))
        snippets[int.parse(match[1]!)].place,
    ];
  }

  /// Starts `dart` with [arguments] and waits for it, killing it when it
  /// runs past [timeLimit] or prints past [outputLimit].
  Future<_Finished> _start(List<String> arguments) async {
    final process = await Process.start(Platform.resolvedExecutable, arguments);
    var hasTimedOut = false;
    final output = _capped(process, process.stdout);
    final errors = _capped(process, process.stderr);
    final exitCode = await process.exitCode.timeout(
      timeLimit,
      onTimeout: () {
        hasTimedOut = true;
        process.kill(ProcessSignal.sigkill);
        return process.exitCode;
      },
    );
    final (outputText, isOutputCut) = await output;
    final (errorText, isErrorCut) = await errors;
    return _Finished(
      exitCode,
      outputText,
      hasTimedOut
          ? 'timed out after $timeLimit'
          : isOutputCut || isErrorCut
          ? 'output exceeded $outputLimit bytes'
          : errorText,
      hasTimedOut: hasTimedOut,
    );
  }

  /// Reads [stream] as text and whether it was cut: past [outputLimit]
  /// bytes this kills [process] and stops reading.
  Future<(String, bool)> _capped(
    Process process,
    Stream<List<int>> stream,
  ) async {
    final bytes = BytesBuilder(copy: false);
    var isCut = false;
    await for (final chunk in stream) {
      bytes.add(chunk);
      if (bytes.length > outputLimit) {
        isCut = true;
        process.kill(ProcessSignal.sigkill);
        break;
      }
    }
    final kept = bytes.takeBytes();
    final end = kept.length < outputLimit ? kept.length : outputLimit;
    return (utf8.decode(kept.sublist(0, end), allowMalformed: true), isCut);
  }

  /// [text] with `\n` line ends and without trailing white space, so the
  /// comparison does not depend on the platform.
  static String _normalized(String text) =>
      text.replaceAll('\r\n', '\n').trimRight();
}

/// What a finished `dart` process left, before the text is normalized.
final class _Finished(
  final int exitCode,
  final String output,
  final String errors, {
  final bool hasTimedOut = false,
}) {
  this;
}
