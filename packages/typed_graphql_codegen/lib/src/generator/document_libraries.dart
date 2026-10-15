import 'package:typed_graphql/typed_graphql.dart';

import '../emit/document_library_emitter.dart';
import '../emit/library_imports.dart';
import '../emit/type_mapper.dart';
import '../plan/operation_text.dart';
import '../plan/shape_planner.dart';
import 'client_project.dart';
import 'generated_file.dart';

/// Generates the library of every document file of a project (spec §7
/// "Files").
final class DocumentLibraries {
  /// Creates the generator for [project]; [schemaTypesPath] is the
  /// schema-types library its libraries import.
  DocumentLibraries(this.project, this.mapper, this.schemaTypesPath)
    : planner = ShapePlanner(project.schema.schema, {
        for (final definition in project.document.document.definitions)
          if (definition is FragmentDefinition)
            definition.name.value: definition,
      });

  /// The project whose document files are generated.
  final ClientProject project;

  /// The mapper of field types.
  final TypeMapper mapper;

  /// The path of the schema-types library.
  final String schemaTypesPath;

  /// The planner of the project's classes.
  final ShapePlanner planner;

  /// The writer of the document texts the operations are sent with.
  OperationText get operationText =>
      OperationText(planner.schema, planner.fragments);

  /// A library per document file, sorted by path.
  List<GeneratedFile> generate() {
    final files = project.documents.files;
    final map = project.documents.sourceMap;
    final definitionsByFile = <int, List<ExecutableDefinition>>{};
    final libraryOf = <String, String>{};
    for (final definition in project.document.document.definitions) {
      if (definition is! ExecutableDefinition) continue;
      final index = map.fileIndexAt(definition.start);
      definitionsByFile.putIfAbsent(index, () => []).add(definition);
      if (definition is! FragmentDefinition) continue;
      libraryOf[definition.name.value] = '${files[index].path}.dart';
    }
    final emitter = DocumentLibraryEmitter(
      planner,
      mapper,
      LibraryImports(project.schema.schema, schemaTypesPath, libraryOf),
    );
    return [
      for (final (int index, file) in files.indexed)
        GeneratedFile(
          emitter.libraryPathOf(file.path),
          emitter.emit(file.path, definitionsByFile[index] ?? const []),
        ),
    ];
  }
}
