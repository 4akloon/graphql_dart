import 'package:typed_graphql/typed_graphql.dart';

import '../documents/project_documents.dart';

/// A schema and the documents validated against it: what the generator reads.
final class ClientProject(
  /// The valid schema.
  final ValidSchema schema,

  /// The project's documents as one fragment graph.
  final ProjectDocuments documents,

  /// The documents, validated with `ClientGenerator.rules`.
  final ValidDocument document,
) {
  /// Creates a project.
  this;
}
