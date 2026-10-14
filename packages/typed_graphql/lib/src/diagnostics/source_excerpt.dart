import 'dart:math';

import 'source.dart';
import 'source_location.dart';

/// Shows a location in a [Source] as graphql-js's `printSourceLocation`
/// does, character for character: `name:line:column`, the line before,
/// the line with a caret under the column, and the line after.
///
/// A line longer than 120 code units, as in a minified document, is shown
/// in 80-unit pieces up to the one after the caret.
final class SourceExcerpt {
  /// Creates the formatter; it keeps no state.
  const SourceExcerpt();

  static final RegExp _lineTerminator = RegExp('\r\n|[\n\r]');

  /// [location] in [source], which must be a location of [source].
  String of(Source source, SourceLocation location) {
    final SourceLocation(:line, :column) = location;
    final lines = source.body.split(_lineTerminator);
    final text = lines[line - 1];
    final header = '${source.name}:$line:$column\n';
    if (text.length > 120) {
      return header + _minified(line, column, text);
    }
    return header +
        _prefixed([
          ('${line - 1} |', line > 1 ? lines[line - 2] : null),
          ('$line |', text),
          ('|', '^'.padLeft(column)),
          ('${line + 1} |', line < lines.length ? lines[line] : null),
        ]);
  }

  /// The long [text] of line [line] cut into 80-unit pieces.
  String _minified(int line, int column, String text) {
    final pieces = [
      for (var start = 0; start < text.length; start += 80)
        text.substring(start, min(start + 80, text.length)),
    ];
    final caretPiece = column ~/ 80;
    return _prefixed([
      ('$line |', pieces.first),
      for (final piece in pieces.skip(1).take(caretPiece)) ('|', piece),
      ('|', '^'.padLeft(column % 80)),
      ('|', caretPiece + 1 < pieces.length ? pieces[caretPiece + 1] : null),
    ]);
  }

  /// The rows whose text exists, each prefix padded to the widest; an
  /// empty text leaves the prefix alone on its row.
  String _prefixed(List<(String, String?)> rows) {
    final present = [
      for (final row in rows)
        if (row case (final prefix, final String text)) (prefix, text),
    ];
    final width = present.map((row) => row.$1.length).reduce(max);
    return [
      for (final (prefix, text) in present)
        prefix.padLeft(width) + (text.isEmpty ? '' : ' $text'),
    ].join('\n');
  }
}
