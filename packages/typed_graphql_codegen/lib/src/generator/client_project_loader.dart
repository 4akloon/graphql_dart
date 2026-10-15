import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';
import '../documents/project_documents.dart';
import '../documents/project_documents_result.dart';
import '../project/project_file.dart';
import '../schema/schema_load_result.dart';
import '../schema/schema_loader.dart';
import 'client_project.dart';
import 'client_project_result.dart';
import 'scalar_mapping_checker.dart';

/// Reads the schema and the documents of a project and validates them with
/// `rules` (`ClientGenerator.rules`); shared by `check` and `generate`.
final class const ClientProjectLoader(
  final CodegenConfig config,
  final List<ValidationRule> rules,
) {
  /// Creates a loader for [config] that validates documents with [rules].
  this;

  /// Loads the project; never throws for bad input.
  ClientProjectResult load({
    required ProjectFile schema,
    required List<ProjectFile> documents,
  }) {
    final read = ProjectDocuments.read(documents);
    return switch (const SchemaLoader().load(schema)) {
      // The documents are read anyway so that one run shows every syntax
      // error.
      SchemaNotLoaded(:final diagnostics) => ClientProjectFailed([
        ...diagnostics,
        if (read case ProjectDocumentsUnreadable(diagnostics: final more))
          ...more,
      ]),
      SchemaLoaded(schema: final valid) => _withSchema(valid, read),
    };
  }

  ClientProjectResult _withSchema(
    ValidSchema schema,
    ProjectDocumentsResult read,
  ) {
    final mapping = const ScalarMappingChecker().check(config, schema.schema);
    return switch (read) {
      ProjectDocumentsUnreadable(:final diagnostics) => ClientProjectFailed([
        ...mapping,
        ...diagnostics,
      ]),
      ProjectDocumentsRead(documents: final files) => _validate(
        schema,
        files,
        mapping,
      ),
    };
  }

  ClientProjectResult _validate(
    ValidSchema schema,
    ProjectDocuments documents,
    List<Diagnostic> mapping,
  ) {
    final warnings = <Diagnostic>[
      if (documents.document.definitions.isEmpty)
        Diagnostic(
          .noDocuments,
          .warning,
          "No document matches the configuration's 'documents'.",
        ),
    ];
    final map = documents.sourceMap;
    final result = DocumentValidator(rules: rules)
        .validate(schema, documents.document, source: map.source);
    return switch (result) {
      InvalidDocument(:final diagnostics) => ClientProjectFailed([
        ...mapping,
        for (final diagnostic in diagnostics)
          map.translateDiagnostic(diagnostic),
        ...warnings,
      ]),
      ValidDocument() when mapping.isNotEmpty => ClientProjectFailed([
        ...mapping,
        ...warnings,
      ]),
      final ValidDocument valid => ClientProjectLoaded(
        ClientProject(schema, documents, valid),
        warnings,
      ),
    };
  }
}
