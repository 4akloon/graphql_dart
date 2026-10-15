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
import 'secret_redactor.dart';

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
    switch (project) {
      case ProjectReadFailed(:final diagnostics, :final secrets):
        return _report(diagnostics, secrets);
      case ProjectRead():
        return _generate(project, directory, isCheck: isCheck);
    }
  }

  int _generate(
    ProjectRead project,
    String directory, {
    required bool isCheck,
  }) {
    final result = ClientGenerator(
      project.config,
    ).generate(schema: project.schema, documents: project.documents);
    final secrets = project.secrets;
    if (result.hasErrors) return _report(result.diagnostics, secrets);
    final writer = OutputWriter(directory);
    if (isCheck) {
      final outdated = writer.outdated(result.files);
      final code = _report([...result.diagnostics, ...outdated], secrets);
      if (outdated.isEmpty) out.writeln('Up to date.');
      return code;
    }
    final (:written, :problems) = writer.write(result.files);
    final code = _report([...result.diagnostics, ...problems], secrets);
    out.writeln(switch (written.length) {
      0 => 'Nothing to write.',
      1 => 'Wrote 1 file.',
      final count => 'Wrote $count files.',
    });
    return code;
  }

  int _report(List<Diagnostic> diagnostics, [List<String> secrets = const []]) {
    final printer = DiagnosticPrinter(SecretRedactor(secrets));
    for (final diagnostic in diagnostics) {
      err.writeln(printer.print(diagnostic));
    }
    return diagnostics.any((diagnostic) => diagnostic.isError) ? 1 : 0;
  }
}
