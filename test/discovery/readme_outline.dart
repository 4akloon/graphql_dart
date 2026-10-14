// The core's documentation suite owns the Markdown readers; the workspace
// suite shares them instead of keeping a copy that could drift.
import '../../packages/typed_graphql/test/doc/markdown_fence.dart';

/// The parts of a README that an agent reads first: the paragraphs before
/// the first section, and the `##` sections. Fenced code is left out, so a
/// `#` comment in a fence is not a heading.
final class ReadmeOutline(String markdown) {
  /// Creates the outline of [markdown].
  this;

  final List<String> _lines = const MarkdownFences().proseLines(markdown);

  static final RegExp _section = RegExp(r'^##\s+(.*?)\s*$');
  static final RegExp _status = RegExp(r'^> \*\*Status: ([^.*]+)\.\*\*');

  /// The `##` headings, in order.
  List<String> get headings => [
    for (final line in _lines)
      if (_section.firstMatch(line) case final match?) match[1]!,
  ];

  /// The paragraphs between the `#` title and the first `##` heading,
  /// badge lines left out; the lines of a paragraph are joined with a
  /// space.
  List<String> get opening {
    final firstSection = _lines.indexWhere(_section.hasMatch);
    return _paragraphs(
      _lines.sublist(1, firstSection < 0 ? _lines.length : firstSection),
    ).where((paragraph) => !paragraph.startsWith(RegExp(r'\[?!\['))).toList();
  }

  /// What the status banner (`> **Status: skeleton.**`) says, such as
  /// `skeleton`, or null when the opening has no banner.
  String? get status =>
      opening.map(_status.firstMatch).nonNulls.firstOrNull?[1];

  /// The text under the `##` heading [heading] up to the next `##`
  /// heading, its lines joined with `\n`; empty when there is no such
  /// heading.
  String section(String heading) {
    final start = _lines.indexWhere(
      (line) => _section.firstMatch(line)?[1] == heading,
    );
    if (start < 0) return '';
    final rest = _lines.sublist(start + 1);
    final end = rest.indexWhere(_section.hasMatch);
    return rest.sublist(0, end < 0 ? rest.length : end).join('\n').trim();
  }

  List<String> _paragraphs(List<String> lines) {
    final paragraphs = <String>[];
    final current = <String>[];
    for (final line in [...lines, '']) {
      if (line.trim().isNotEmpty) {
        current.add(line.trim());
      } else if (current.isNotEmpty) {
        paragraphs.add(current.join(' '));
        current.clear();
      }
    }
    return paragraphs;
  }
}
