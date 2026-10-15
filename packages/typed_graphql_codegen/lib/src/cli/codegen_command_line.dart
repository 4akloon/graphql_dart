import 'package:args/args.dart';

import 'command_line_result.dart';

/// The command line of the code generator: `generate` or `check`, and
/// `--config`.
///
/// {@category codegen}
final class const CodegenCommandLine() {
  /// Creates the parser.
  this;

  /// The configuration file name when `--config` is not given.
  static const String defaultConfigPath = 'typed_graphql.yaml';

  /// The usage text shown for `--help` and after a usage error.
  String get usage =>
      'Usage: typed_graphql_codegen <generate|check> [--config <file>]\n\n'
      'Commands:\n'
      '  generate  Write the generated files.\n'
      '  check     Fail when a generated file is missing or out of date.\n\n'
      '${_parser.usage}';

  static final ArgParser _parser = ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      defaultsTo: defaultConfigPath,
      help: 'The configuration file.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  /// Reads [arguments]; a mistake is a [CommandLineUsageError], never a throw.
  CommandLineResult parse(List<String> arguments) {
    final ArgResults results;
    try {
      results = _parser.parse(arguments);
    } on FormatException catch (error) {
      return CommandLineUsageError(error.message);
    }
    if (results.flag('help')) return const CommandLineHelp();
    final rest = results.rest;
    if (rest.isEmpty) return const CommandLineUsageError('Missing command.');
    if (rest.length > 1 ||
        (rest.single != 'generate' && rest.single != 'check')) {
      return CommandLineUsageError('Unknown command "${rest.join(' ')}".');
    }
    return CommandLineRun(
      rest.single == 'check',
      results.option('config') ?? defaultConfigPath,
    );
  }
}
