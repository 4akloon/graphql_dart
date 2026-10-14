import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/diagnostic_code.dart';
import '../../diagnostics/diagnostic_sink.dart';
import '../../diagnostics/source.dart';
import '../../diagnostics/source_span.dart';
import 'character_class.dart';

/// What the scanners of one lexer share: the text, its characters and the
/// sink errors go to.
final class SourceReader {
  /// Creates a reader of [source] that reports into [sink].
  SourceReader(this.source, this.sink);

  /// The document being read.
  final Source source;

  /// Where errors are reported.
  final DiagnosticSink sink;

  static const CharacterClass _classes = CharacterClass();

  /// The number of code units in the document.
  int get length => source.body.length;

  /// The code unit at [offset], or -1 at and past the end.
  int unitAt(int offset) =>
      offset < source.body.length ? source.body.codeUnitAt(offset) : -1;

  /// The text from [start] to [end], cut at the end of the document.
  String slice(int start, int end) =>
      source.body.substring(start, end < length ? end : length);

  /// The code units of the source character at [offset]: 1, 2 for a
  /// surrogate pair, or 0 when it is a lone surrogate or the end.
  int characterWidthAt(int offset) {
    final unit = unitAt(offset);
    if (_classes.isScalarValue(unit)) {
      return 1;
    }
    final isPair =
        _classes.isLeadingSurrogate(unit) &&
        _classes.isTrailingSurrogate(unitAt(offset + 1));
    return isPair ? 2 : 0;
  }

  /// The character at [offset] as messages show it, as graphql-js's
  /// `printCodePointAt` does: `"a"`, `'"'`, `U+0007`, `U+1F600` or
  /// `<EOF>`.
  String describe(int offset) {
    final unit = unitAt(offset);
    if (unit < 0) {
      return '<EOF>';
    }
    if (unit >= 0x20 && unit <= 0x7e) {
      final character = String.fromCharCode(unit);
      return character == '"' ? "'\"'" : '"$character"';
    }
    final point = characterWidthAt(offset) == 2
        ? 0x10000 + ((unit - 0xd800) << 10) + (unitAt(offset + 1) - 0xdc00)
        : unit;
    return 'U+${point.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  /// Reports an error with [code] and [message] over [start] to [end].
  void report(DiagnosticCode code, String message, int start, int end) {
    final span = SourceSpan(source, start, end < length ? end : length);
    sink.report(Diagnostic(code, .error, message, span: span));
  }
}
