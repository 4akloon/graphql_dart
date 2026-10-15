import 'package:typed_graphql/typed_graphql.dart';

import '../project/project_file.dart';

/// Maps offsets of the project text, every file joined by a line break, back
/// to the file they came from.
///
/// Each file occupies `[start, start + text.length]` of [text]; the line
/// break after it belongs to that file, so an offset on it maps to the file
/// before it.
final class ProjectSourceMap(List<ProjectFile> files) {
  /// Creates a map of [files], which are already in project order.
  this;

  final List<Source> _sources = [
    for (final file in files) Source(file.text, name: file.path),
  ];

  final List<int> _starts = _startsOf(files);

  /// The project text: every file's text followed by a line break.
  final String text = [for (final file in files) '${file.text}\n'].join();

  /// The project text as one [Source], named `<project>`.
  // late: it reads [text], which is initialised before the first access.
  late final Source source = Source(text, name: '<project>');

  static List<int> _startsOf(List<ProjectFile> files) {
    final starts = <int>[];
    var offset = 0;
    for (final file in files) {
      starts.add(offset);
      offset += file.text.length + 1;
    }
    return starts;
  }

  /// The index of the file that holds [offset].
  int fileIndexAt(int offset) {
    RangeError.checkValueInInterval(offset, 0, text.length, 'offset');
    var low = 0;
    var high = _starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_starts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// The path of the file that holds [offset].
  String pathAt(int offset) => _sources[fileIndexAt(offset)].name;

  /// [span] of the project source as a span of its file.
  ///
  /// A span from another source is returned as it is.
  SourceSpan translate(SourceSpan span) {
    if (!identical(span.source, source)) {
      return span;
    }
    final index = fileIndexAt(span.start);
    final fileSource = _sources[index];
    final fileStart = _starts[index];
    final end = span.end - fileStart;
    return SourceSpan(
      fileSource,
      span.start - fileStart,
      // A span can end on the joining line break, which is not in the file.
      end > fileSource.body.length ? fileSource.body.length : end,
    );
  }

  /// [diagnostic] with its span and related spans translated by [translate].
  Diagnostic translateDiagnostic(Diagnostic diagnostic) {
    final span = diagnostic.span;
    return Diagnostic(
      diagnostic.code,
      diagnostic.severity,
      diagnostic.message,
      span: span == null ? null : translate(span),
      related: [for (final place in diagnostic.related) translate(place)],
    );
  }
}
