import 'package:path/path.dart' as p;
import 'package:typed_graphql/typed_graphql.dart';

import '../generator/client_generator.dart';
import 'codegen_command_line.dart';
import 'command_line_result.dart';
import 'diagnostic_printer.dart';
import 'output_writer.dart';
import 'project_read_result.dart';
import 'project_reader.dart';
import 'schema_fetcher.dart';

/// Runs the code generator's command line, with injected streams and working
/// directory so tests run it in process.
///
/// {@category codegen}
final class CodegenCommand {
  /// Creates a command that writes to [out] and [err]; [environment] feeds
  /// the `${NAME}` references of the headers (`bin/` passes the process's)
  /// and [fetcher] gets a schema URL.
  const CodegenCommand(
    this.out,
    this.err,
    this.workingDirectory, {
    this.environment = const {},
    this.fetcher = const SchemaFetcher(),
  });

  /// Where normal output goes.
  final StringSink out;

  /// Where diagnostics and usage errors go.
  final StringSink err;

  /// The directory relative `--config` paths are resolved against.
  final String workingDirectory;

  /// The environment variables the header values may reference.
  final Map<String, String> environment;

  /// What fetches a schema URL.
  final SchemaFetcher fetcher;

  /// The exit code of a usage error.
  static const int usageExitCode = 64;

  /// Runs [arguments]; returns the process exit code.
  Future<int> run(List<String> arguments) async {
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
        return await _run(isCheck: isCheck, configPath: configPath);
    }
  }

  Future<int> _run({
    required bool isCheck,
    required String configPath,
  }) async {
    final absolute = p.normalize(p.absolute(workingDirectory, configPath));
    final directory = p.dirname(absolute);
    final project = await ProjectReader(
      directory,
      environment: environment,
      fetcher: fetcher,
    ).read(p.basename(absolute));
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
