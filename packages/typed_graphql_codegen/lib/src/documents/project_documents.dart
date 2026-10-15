import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';
import 'project_documents_result.dart';
import 'project_source_map.dart';

/// The project's `.graphql` files read as one document, so that a fragment
/// is visible from every operation (R7.2).
///
/// The document's offsets index [ProjectSourceMap.source]; the map gives the
/// file of each offset. A file with no tokens adds nothing. Documents are
/// parsed with the parser's default limits, except that the token limit is
/// lifted.
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
    if (sorted.every(_isBlank)) {
      // An empty text is a syntax error (spec §2.2), so the empty document is
      // built.
      return ProjectDocumentsRead(
        ProjectDocuments(sorted, map, Document(const [])),
      );
    }
    // Each file parsed alone, but the joined text can still fail: a file
    // ending in `extend enum E @d` makes the next file's leading `{` the
    // extension's body. The core parser cannot start at an offset, so the
    // joined text is parsed again and its problems are translated.
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
      if (_isBlank(file)) continue;
      final result = const Parser().parse(Source(file.text, name: file.path));
      if (result is ParseFailure) {
        problems.addAll(result.diagnostics);
      }
    }
    return problems;
  }

  // Only ignored tokens (whitespace, commas, comments, BOM): the file adds no
  // definition and is not a syntax error.
  static bool _isBlank(ProjectFile file) =>
      Lexer(
        Source(file.text, name: file.path),
        DiagnosticSink(),
      ).advance().kind ==
      TokenKind.eof;
}
