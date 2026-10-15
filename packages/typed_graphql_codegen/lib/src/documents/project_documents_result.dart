import 'package:typed_graphql/typed_graphql.dart';

import 'project_documents.dart';

/// The result of reading the project's documents: [ProjectDocumentsRead] or
/// [ProjectDocumentsUnreadable].
sealed class ProjectDocumentsResult {
  /// Creates a result.
  const ProjectDocumentsResult();
}

/// Every file parsed.
final class ProjectDocumentsRead(
  /// The documents as one fragment graph.
  final ProjectDocuments documents,
) extends ProjectDocumentsResult {
  /// Creates a success.
  this;
}

/// At least one file has a syntax error.
final class ProjectDocumentsUnreadable(List<Diagnostic> diagnostics)
    extends ProjectDocumentsResult {
  /// Creates a failure.
  this;

  /// Every diagnostic of every file that failed, in path order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);
}
