import 'llms_entry.dart';

/// An `llms.txt` file in the llmstxt.org shape: a `#` title, a `>`
/// summary, then `##` sections whose lines are links with a description.
final class LlmsText(String text) {
  /// Reads [text].
  this;

  final List<String> _lines = text.replaceAll('\r\n', '\n').split('\n');

  static final RegExp _entry = RegExp(
    r'^- \[([^\]]+)\]\((\S+)\)(?::\s*(.*))?$',
  );

  /// The `#` headings, in order.
  List<String> get titles => [
    for (final line in _lines)
      if (line.startsWith('# ')) line.substring(2).trim(),
  ];

  /// The blockquotes: each run of `>` lines, joined with a space.
  List<String> get summaries {
    final summaries = <String>[];
    final current = <String>[];
    for (final line in [..._lines, '']) {
      if (line.startsWith('>')) {
        current.add(line.substring(1).trim());
      } else if (current.isNotEmpty) {
        summaries.add(current.join(' '));
        current.clear();
      }
    }
    return summaries;
  }

  /// The `##` headings, in order.
  List<String> get sections => [
    for (final line in _lines)
      if (line.startsWith('## ')) line.substring(3).trim(),
  ];

  /// The link lines of the section [heading], in order; empty when there
  /// is no such section.
  List<LlmsEntry> entriesOf(String heading) {
    final start = _lines.indexOf('## $heading');
    if (start < 0) return const [];
    return [
      for (final line in _lines.skip(start + 1).takeWhile(_isInSection))
        if (_entry.firstMatch(line) case final match?)
          LlmsEntry(match[1]!, match[2]!, match[3] ?? ''),
    ];
  }

  bool _isInSection(String line) => !line.startsWith('## ');
}
