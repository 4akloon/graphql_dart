import 'package:typed_graphql/typed_graphql.dart';

import 'codegen_config.dart';

/// The outcome of [CodegenConfig.parse]: a configuration or the problems that
/// stop one.
///
/// {@category codegen}
sealed class const ConfigResult() {
  /// Creates a result.
  this;
}

/// A configuration that was read without errors.
///
/// {@category codegen}
final class ConfigSuccess(
  /// The configuration.
  final CodegenConfig config,
) extends ConfigResult {
  /// Creates a success holding [config].
  this;
}

/// A configuration that has errors.
///
/// {@category codegen}
final class ConfigFailure(
  List<Diagnostic> diagnostics,
) extends ConfigResult {
  /// Creates a failure with [diagnostics].
  this;

  /// The problems, in document order; never empty.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
