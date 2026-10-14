/// One fenced code block of a Markdown file.
final class MarkdownFence(
  /// The text after the opening marker, such as `dart` or `text`.
  final String info,

  /// The lines inside the fence, joined with `\n`.
  final String body,

  /// The 1-based line of the opening marker.
  final int line,

  /// The prose between the previous fence and this one, trimmed lines
  /// joined with `\n`; empty when the fences are only blank lines apart.
  final String precedingText,
) {
  /// Creates a fence.
  this;
}

/// Finds the fenced code blocks of Markdown text, by CommonMark's rules: an
/// opening of three or more backticks or tildes, indented by at most three
/// spaces, closed by a line of the same character at least as long.
///
/// Every test that must skip code reads fences here, so the rules cannot
/// drift apart.
final class MarkdownFences {
  /// Creates the reader.
  const MarkdownFences();

  static final RegExp _opening = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');

  /// The fences of [markdown], in order. An unclosed fence is a
  /// [FormatException].
  List<MarkdownFence> of(String markdown) {
    final lines = _linesOf(markdown);
    final fences = <MarkdownFence>[];
    final prose = <String>[];
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      final opening = _opening.firstMatch(line);
      // A backtick fence's info cannot hold a backtick (`code` in prose).
      if (opening == null || _isInlineCode(opening)) {
        if (line.trim().isNotEmpty) prose.add(line.trim());
        index++;
        continue;
      }
      final closing = _closingLine(lines, index, opening[1]!);
      fences.add(
        MarkdownFence(
          opening[2]!.trim(),
          lines.sublist(index + 1, closing).join('\n'),
          index + 1,
          prose.join('\n'),
        ),
      );
      prose.clear();
      index = closing + 1;
    }
    return fences;
  }

  /// The lines of [markdown] with each fence, markers included, replaced by
  /// empty lines, so line numbers stay. An unclosed fence is a
  /// [FormatException].
  List<String> proseLines(String markdown) {
    final lines = _linesOf(markdown);
    for (final fence in of(markdown)) {
      final count = fence.body.isEmpty ? 0 : fence.body.split('\n').length;
      for (var line = fence.line - 1; line <= fence.line + count; line++) {
        lines[line] = '';
      }
    }
    return lines;
  }

  List<String> _linesOf(String markdown) =>
      markdown.replaceAll('\r\n', '\n').split('\n');

  bool _isInlineCode(RegExpMatch opening) =>
      opening[1]!.startsWith('`') && opening[2]!.contains('`');

  int _closingLine(List<String> lines, int opened, String marker) {
    final closing = RegExp(
      '^ {0,3}${marker[0]}{${marker.length},}\\s*\$',
    );
    for (var index = opened + 1; index < lines.length; index++) {
      if (closing.hasMatch(lines[index])) return index;
    }
    throw FormatException('Unclosed fence at line ${opened + 1}');
  }
}
