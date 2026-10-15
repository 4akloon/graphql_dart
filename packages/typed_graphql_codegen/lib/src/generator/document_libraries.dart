import 'package:typed_graphql/typed_graphql.dart';

import '../emit/document_library_emitter.dart';
import '../emit/library_imports.dart';
import '../emit/type_mapper.dart';
import '../plan/shape_planner.dart';
import 'client_project.dart';
import 'generated_file.dart';

/// Generates the library of every document file of a project (spec §7
/// "Files").
final class DocumentLibraries {
  /// Creates the generator for [project]; [schemaTypesPath] is the
  /// schema-types library its libraries import.
  const DocumentLibraries(this.project, this.mapper, this.schemaTypesPath);

  /// The project whose document files are generated.
  final ClientProject project;

  /// The mapper of field types.
  final TypeMapper mapper;

  /// The path of the schema-types library.
  final String schemaTypesPath;

  /// A library per document file, sorted by path.
  List<GeneratedFile> generate() {
    final files = project.documents.files;
    final map = project.documents.sourceMap;
    final definitionsByFile = <int, List<ExecutableDefinition>>{};
    final fragmentsByName = <String, FragmentDefinition>{};
    final libraryOf = <String, String>{};
    for (final definition in project.document.document.definitions) {
      if (definition is! ExecutableDefinition) continue;
      final index = map.fileIndexAt(definition.start);
      definitionsByFile.putIfAbsent(index, () => []).add(definition);
      if (definition is! FragmentDefinition) continue;
      fragmentsByName[definition.name.value] = definition;
      libraryOf[definition.name.value] = '${files[index].path}.dart';
    }
    final emitter = DocumentLibraryEmitter(
      ShapePlanner(project.schema.schema, fragmentsByName),
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
