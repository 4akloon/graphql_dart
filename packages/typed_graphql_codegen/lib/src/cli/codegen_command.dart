import 'package:path/path.dart' as p;
import 'package:typed_graphql/typed_graphql.dart';

import '../generator/client_generator.dart';
import 'codegen_command_line.dart';
import 'command_line_result.dart';
import 'diagnostic_printer.dart';
import 'output_writer.dart';
import 'project_read_result.dart';
import 'project_reader.dart';

/// Runs the code generator's command line, with injected streams and working
/// directory so tests run it in process.
///
/// {@category codegen}
final class const CodegenCommand(
  /// Where normal output goes.
  final StringSink out,

  /// Where diagnostics and usage errors go.
  final StringSink err,

  /// The directory relative `--config` paths are resolved against.
  final String workingDirectory,
) {
  /// Creates a command that writes to [out] and [err].
  this;

  /// The exit code of a usage error.
  static const int usageExitCode = 64;

  /// Runs [arguments]; returns the process exit code.
  int run(List<String> arguments) {
    const commandLine = CodegenCommandLine();
    switch (commandLine.parse(arguments)) {
      case CommandLineHelp():
        out.writeln(commandLine.usage);
        return 0;
      case CommandLineUsageError(:final message):
        err.writeln(message);
        err.writeln(commandLine.usage);
        return usageExitCode;
      case CommandLineRun(:final isCheck, :final configPath):
        return _run(isCheck: isCheck, configPath: configPath);
    }
  }

  int _run({required bool isCheck, required String configPath}) {
    final absolute = p.normalize(p.absolute(workingDirectory, configPath));
    final directory = p.dirname(absolute);
    final project = ProjectReader(directory).read(p.basename(absolute));
    if (project is! ProjectRead) {
      return _report((project as ProjectReadFailed).diagnostics);
    }
    final result = ClientGenerator(
      project.config,
    ).generate(schema: project.schema, documents: project.documents);
    if (result.hasErrors) return _report(result.diagnostics);
    final writer = OutputWriter(directory);
    if (isCheck) {
      final outdated = writer.outdated(result.files);
      final code = _report([...result.diagnostics, ...outdated]);
      if (outdated.isEmpty) out.writeln('Up to date.');
      return code;
    }
    final written = writer.write(result.files);
    final code = _report(result.diagnostics);
    out.writeln(
      written.isEmpty ? 'Nothing to write.' : 'Wrote ${written.length} files.',
    );
    return code;
  }

  int _report(List<Diagnostic> diagnostics) {
    const printer = DiagnosticPrinter();
    for (final diagnostic in diagnostics) {
      err.writeln(printer.print(diagnostic));
    }
    return diagnostics.any((diagnostic) => diagnostic.isError) ? 1 : 0;
  }
}
