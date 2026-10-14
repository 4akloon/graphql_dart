import 'dart:io';

import 'markdown_fence.dart';

/// A link to a place in the repository, as a Markdown file writes it.
final class MarkdownLink(
  /// The 1-based line of the link in its file.
  final int line,

  /// What follows `](`: a path, a path with `#anchor`, or just `#anchor`.
  final String target,
) {
  /// Creates a link.
  this;
}

/// Finds the relative links and the anchors of Markdown text. Web links
/// are left alone: the tests run offline.
final class MarkdownLinks {
  /// Creates the reader.
  const MarkdownLinks();

  static final RegExp _link = RegExp(r'\[[^\]]*\]\(([^)\s]+)\)');
  static final RegExp _heading = RegExp(r'^#{1,6}\s+(.*?)\s*#*\s*$');
  static final RegExp _web = RegExp('^(?:[a-z][a-z0-9+.-]*:)');

  /// The links of [markdown] that point inside the repository, fenced code
  /// left out.
  List<MarkdownLink> relativeIn(String markdown) => [
    for (final (index, line) in _prose(markdown).indexed)
      for (final match in _link.allMatches(line))
        if (!_web.hasMatch(match[1]!)) MarkdownLink(index + 1, match[1]!),
  ];

  /// The text of the file at [path], the target of a link with an anchor. A
  /// path that is not a file is a [FormatException] saying so, as a
  /// directory has no headings to point at.
  String readTarget(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FormatException('"$path" is not a file, so it has no anchors');
    }
    return file.readAsStringSync();
  }

  /// The anchors GitHub gives the headings of [markdown]: the text in
  /// lower case without punctuation, spaces as hyphens, `-1`, `-2` for a
  /// repeated heading.
  Set<String> anchorsIn(String markdown) {
    final counts = <String, int>{};
    final anchors = <String>{};
    for (final line in _prose(markdown)) {
      final text = _heading.firstMatch(line)?[1];
      if (text == null) continue;
      final slug = text
          .toLowerCase()
          .replaceAll(RegExp('[^a-z0-9 _-]'), '')
          .replaceAll(' ', '-');
      final seen = counts[slug] ?? 0;
      counts[slug] = seen + 1;
      anchors.add(seen == 0 ? slug : '$slug-$seen');
    }
    return anchors;
  }

  List<String> _prose(String markdown) =>
      const MarkdownFences().proseLines(markdown);
}
