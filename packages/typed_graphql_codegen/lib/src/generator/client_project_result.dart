import 'package:typed_graphql/typed_graphql.dart';

import 'client_project.dart';

/// The outcome of loading a project: [ClientProjectLoaded] or
/// [ClientProjectFailed].
sealed class ClientProjectResult {
  /// Creates a result.
  const ClientProjectResult();
}

/// A project that can be generated from.
final class ClientProjectLoaded(
  /// The project.
  final ClientProject project,
  List<Diagnostic> warnings,
) extends ClientProjectResult {
  /// Creates a success.
  this;

  /// The warnings, in report order.
  final List<Diagnostic> warnings = List.unmodifiable(warnings);
}

/// A project with errors.
final class ClientProjectFailed(List<Diagnostic> diagnostics)
    extends ClientProjectResult {
  /// Creates a failure.
  this;

  /// Every diagnostic, in report order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
