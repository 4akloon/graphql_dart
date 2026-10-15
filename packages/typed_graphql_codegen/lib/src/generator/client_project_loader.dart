import 'package:typed_graphql/typed_graphql.dart';

import '../config/codegen_config.dart';
import '../documents/project_documents.dart';
import '../documents/project_documents_result.dart';
import '../project/project_file.dart';
import '../schema/schema_load_result.dart';
import '../schema/schema_loader.dart';
import 'client_generator.dart';
import 'client_project.dart';
import 'client_project_result.dart';
import 'scalar_mapping_checker.dart';

/// Reads the schema and the documents of a project and validates them with
/// [ClientGenerator.rules]; shared by `check` and `generate`.
final class const ClientProjectLoader(final CodegenConfig config) {
  /// Creates a loader for [config].
  this;

  /// Loads the project; never throws for bad input.
  ClientProjectResult load({
    required ProjectFile schema,
    required List<ProjectFile> documents,
  }) {
    final read = ProjectDocuments.read(documents);
    final loaded = const SchemaLoader().load(schema);
    if (loaded is! SchemaLoaded) {
      // The documents are read anyway so that one run shows every syntax
      // error.
      return ClientProjectFailed([
        if (loaded is SchemaNotLoaded) ...loaded.diagnostics,
        if (read is ProjectDocumentsUnreadable) ...read.diagnostics,
      ]);
    }
    final mapping = const ScalarMappingChecker().check(
      config,
      loaded.schema.schema,
    );
    return switch (read) {
      ProjectDocumentsUnreadable(:final diagnostics) => ClientProjectFailed([
        ...mapping,
        ...diagnostics,
      ]),
      ProjectDocumentsRead(documents: final files) => _validate(
        loaded.schema,
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
      if (documents.files.isEmpty)
        Diagnostic(
          .noDocuments,
          .warning,
          "No document matches the configuration's 'documents'.",
        ),
    ];
    final map = documents.sourceMap;
    final result = const DocumentValidator(rules: ClientGenerator.rules)
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
