/// One fenced code block of a Markdown file.
final class MarkdownFence(
  /// The text after the opening backticks, such as `dart` or `text`.
  final String info,

  /// The lines inside the fence, joined with `\n`.
  final String body,

  /// The 1-based line of the opening backticks.
  final int line,

  /// The prose between the previous fence and this one, trimmed lines
  /// joined with `\n`; empty when the fences are only blank lines apart.
  final String precedingText,
) {
  /// Creates a fence.
  this;
}

/// Finds the fenced code blocks of Markdown text.
///
/// Only fences that start a line with three backticks are read, which is
/// how every guide writes them.
final class MarkdownFences {
  /// Creates the reader.
  const MarkdownFences();

  /// The fences of [markdown], in order. An unclosed fence is a
  /// [FormatException].
  List<MarkdownFence> of(String markdown) {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final fences = <MarkdownFence>[];
    final prose = <String>[];
    var index = 0;
    while (index < lines.length) {
      final line = lines[index];
      if (!line.startsWith('```')) {
        if (line.trim().isNotEmpty) prose.add(line.trim());
        index++;
        continue;
      }
      final closing = lines.indexOf('```', index + 1);
      if (closing < 0) {
        throw FormatException('Unclosed fence at line ${index + 1}');
      }
      fences.add(
        MarkdownFence(
          line.substring(3).trim(),
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
}
