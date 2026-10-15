import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';
import '../project/project_file.dart';

/// What [ProjectReader] found on disk.
///
/// {@category codegen}
sealed class ProjectReadResult {
  const ProjectReadResult();
}

/// Everything the generator reads.
///
/// {@category codegen}
final class ProjectRead(
  /// The parsed configuration.
  final CodegenConfig config,

  /// The schema file.
  final ProjectFile schema,
  List<ProjectFile> documents,

  /// The texts to hide when anything of this project is printed, such as the
  /// expanded header values.
  final List<String> secrets,
) extends ProjectReadResult {
  /// Creates the result.
  this;

  /// The matched documents, sorted by path.
  final List<ProjectFile> documents = List.unmodifiable(documents);
}

/// The project could not be read; [diagnostics] say why.
///
/// {@category codegen}
final class ProjectReadFailed(
  List<Diagnostic> diagnostics, [

  /// The texts to hide when the problems are printed.
  final List<String> secrets = const [],
]) extends ProjectReadResult {
  /// Creates the result.
  this;

  /// The problems, in report order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
