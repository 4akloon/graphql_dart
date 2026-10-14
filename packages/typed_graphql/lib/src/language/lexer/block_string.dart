import 'dart:math';

/// The block string algorithms: the value of a block string
/// (`BlockStringValue`, spec §2.9.4) and how a printer writes one, ported
/// from graphql-js's `blockString.ts` so printed output matches.
///
/// {@category language}
final class BlockString {
  /// Creates the algorithms; they keep no state.
  const BlockString();

  static final RegExp _lineTerminator = RegExp('\r\n|[\n\r]');

  /// The value of a block string whose raw text, between the quotes and
  /// with `\"""` already unescaped, is [raw].
  String valueOf(String raw) =>
      dedentLines(raw.split(_lineTerminator)).join('\n');

  /// [lines] without the common indentation of all lines but the first
  /// and without leading and trailing blank lines.
  List<String> dedentLines(List<String> lines) {
    int? commonIndent;
    int? firstNonEmpty;
    var lastNonEmpty = -1;
    for (var i = 0; i < lines.length; i++) {
      final indent = _leadingWhiteSpace(lines[i]);
      if (indent == lines[i].length) {
        continue;
      }
      firstNonEmpty ??= i;
      lastNonEmpty = i;
      if (i != 0 && (commonIndent == null || indent < commonIndent)) {
        commonIndent = indent;
      }
    }
    final indent = commonIndent ?? 0;
    return [
      for (var i = firstNonEmpty ?? 0; i <= lastNonEmpty; i++)
        _withoutIndent(lines[i], i == 0 ? 0 : indent),
    ];
  }

  /// Whether [value] prints as a block string with the same value: no
  /// control characters, no `\r`, no leading or trailing empty line and
  /// no indentation common to every line.
  bool isPrintable(String value) {
    if (value.isEmpty) {
      return true;
    }
    final scan = _PrintableScan();
    for (final unit in value.codeUnits) {
      if (!scan.accept(unit)) {
        return false;
      }
    }
    return !scan.isEmptyLine &&
        !(scan.hasCommonIndent && scan.seenNonEmptyLine);
  }

  /// [value] as block string source, `"""` included: on separate lines
  /// unless [isMinified] or it reads better on one line.
  String print(String value, {bool isMinified = false}) {
    final escaped = value.replaceAll('"""', r'\"""');
    final lines = escaped.split(_lineTerminator);
    final isSingleLine = lines.length == 1;
    final forceLeadingNewLine =
        lines.length > 1 &&
        lines
            .skip(1)
            .every((line) => line.isEmpty || _isWhiteSpace(line.codeUnitAt(0)));
    final hasTrailingTripleQuotes = escaped.endsWith(r'\"""');
    final forceTrailingNewLine =
        (value.endsWith('"') && !hasTrailingTripleQuotes) ||
        value.endsWith(r'\');
    final printAsMultipleLines =
        !isMinified &&
        (!isSingleLine ||
            value.length > 70 ||
            forceTrailingNewLine ||
            forceLeadingNewLine ||
            hasTrailingTripleQuotes);
    final skipLeadingNewLine =
        isSingleLine && value.isNotEmpty && _isWhiteSpace(value.codeUnitAt(0));
    final leading =
        (printAsMultipleLines && !skipLeadingNewLine) || forceLeadingNewLine;
    final trailing = printAsMultipleLines || forceTrailingNewLine;
    return '"""${leading ? '\n' : ''}$escaped${trailing ? '\n' : ''}"""';
  }

  static String _withoutIndent(String line, int indent) =>
      line.substring(min(indent, line.length));

  static int _leadingWhiteSpace(String line) {
    var i = 0;
    while (i < line.length && _isWhiteSpace(line.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  static bool _isWhiteSpace(int unit) => unit == 0x09 || unit == 0x20;
}

/// The state of [BlockString.isPrintable] as it reads a value.
final class _PrintableScan {
  bool isEmptyLine = true;
  bool hasIndent = false;
  bool hasCommonIndent = true;
  bool seenNonEmptyLine = false;

  /// Reads one code unit; false when the value cannot be a block string.
  bool accept(int unit) {
    switch (unit) {
      case 0x0d || <= 0x08 || 0x0b || 0x0c || 0x0e || 0x0f:
        return false;
      case 0x0a:
        if (isEmptyLine && !seenNonEmptyLine) {
          return false;
        }
        seenNonEmptyLine = true;
        isEmptyLine = true;
        hasIndent = false;
      case 0x09 || 0x20:
        hasIndent = hasIndent || isEmptyLine;
      default:
        hasCommonIndent = hasCommonIndent && hasIndent;
        isEmptyLine = false;
    }
    return true;
  }
}
