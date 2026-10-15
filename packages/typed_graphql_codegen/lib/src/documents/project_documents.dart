import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';
import 'project_documents_result.dart';
import 'project_source_map.dart';

/// The project's `.graphql` files read as one document, so that a fragment
/// is visible from every operation (R7.2).
///
/// The document's offsets index [ProjectSourceMap.source]; the map gives the
/// file of each offset.
final class ProjectDocuments(
  /// The files, sorted by path.
  final List<ProjectFile> files,

  /// The map from project offsets to files.
  final ProjectSourceMap sourceMap,

  /// Every definition of every file, in path order.
  final Document document,
) {
  /// Creates the documents.
  this;

  /// Parses [files]; two files with one path are an [ArgumentError].
  static ProjectDocumentsResult read(List<ProjectFile> files) {
    final sorted = [...files]..sort((a, b) => a.path.compareTo(b.path));
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].path == sorted[i - 1].path) {
        throw ArgumentError.value(
          files,
          'files',
          'two files have the path ${sorted[i].path}',
        );
      }
    }
    final problems = _parseEach(sorted);
    if (problems.isNotEmpty) {
      return ProjectDocumentsUnreadable(problems);
    }
    final map = ProjectSourceMap(sorted);
    if (sorted.isEmpty) {
      // An empty text is a syntax error, so the empty document is built.
      return ProjectDocumentsRead(
        ProjectDocuments(sorted, map, Document(const [])),
      );
    }
    // Each file parsed alone and ends at a token boundary, and the joining
    // line break ends a trailing comment, so the whole cannot fail; the
    // branch is defensive.
    final whole = const Parser(
      options: ParserOptions(maxTokens: null),
    ).parse(map.source);
    return switch (whole) {
      ParseSuccess(:final document) => ProjectDocumentsRead(
        ProjectDocuments(sorted, map, document),
      ),
      ParseFailure(:final diagnostics) => ProjectDocumentsUnreadable([
        for (final diagnostic in diagnostics)
          map.translateDiagnostic(diagnostic),
      ]),
    };
  }

  // Every file is parsed before reporting: a missing fragment would turn each
  // spread of it into a second, misleading error.
  static List<Diagnostic> _parseEach(List<ProjectFile> sorted) {
    final problems = <Diagnostic>[];
    for (final file in sorted) {
      final result = const Parser().parse(Source(file.text, name: file.path));
      if (result is ParseFailure) {
        problems.addAll(result.diagnostics);
      }
    }
    return problems;
  }
}
