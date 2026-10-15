/// What [CodegenCommandLine.parse] found.
///
/// {@category codegen}
sealed class CommandLineResult {
  const CommandLineResult();
}

/// Run `generate`, or `check` when [isCheck].
///
/// {@category codegen}
final class const CommandLineRun(
  /// Whether the command is `check`.
  final bool isCheck,

  /// The configuration file path as given.
  final String configPath,
) extends CommandLineResult {
  /// Creates a run request.
  this;
}

/// `--help` was given.
///
/// {@category codegen}
final class const CommandLineHelp() extends CommandLineResult {
  /// Creates the request.
  this;
}

/// The arguments are wrong; [message] says how.
///
/// {@category codegen}
final class const CommandLineUsageError(
  /// What is wrong.
  final String message,
) extends CommandLineResult {
  /// Creates the error.
  this;
}
