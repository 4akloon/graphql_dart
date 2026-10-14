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
/// are left alone: the tests run offline. Only Markdown syntax is read: an
/// HTML `<a href>` or `<img src>` is not checked.
final class MarkdownLinks {
  /// Creates the reader.
  const MarkdownLinks();

  // An inline link may carry a quoted title after the target; a reference
  // definition (`[a]: path`) starts its line. The match starts at `](`, so
  // both targets of a linked image `[![alt](img)](page)` are found.
  static final RegExp _link = RegExp(
    r'\]\(([^)\s]+)(?:\s+(?:"[^"]*"|'
    "'[^']*'"
    r'))?\)',
  );
  static final RegExp _definition = RegExp(r'^\s*\[[^\]]+\]:\s*(\S+)');
  static final RegExp _heading = RegExp(r'^#{1,6}\s+(.*?)\s*#*\s*$');
  static final RegExp _web = RegExp('^(?:[a-z][a-z0-9+.-]*:)');

  /// The links of [markdown] that point inside the repository, fenced code
  /// left out.
  List<MarkdownLink> relativeIn(String markdown) => [
    for (final (index, line) in _prose(markdown).indexed)
      for (final match in [
        ..._link.allMatches(line),
        ?_definition.firstMatch(line),
      ])
        if (!_web.hasMatch(match[1]!)) MarkdownLink(index + 1, match[1]!),
  ];

  /// Why the link [target], written in the file at [from], leads nowhere,
  /// or null when it leads to a file or folder and, with an anchor, to a
  /// heading of that file. Both paths are from the folder the tests run in.
  String? problemOf(String from, String target) {
    final uri = Uri.parse(from).resolve(target);
    if (FileSystemEntity.typeSync(uri.path) == .notFound) {
      return '${uri.path} does not exist';
    }
    if (uri.fragment.isEmpty) return null;
    final anchors = anchorsIn(readTarget(uri.path));
    if (anchors.contains(uri.fragment)) return null;
    return '${uri.path} has no heading with the anchor #${uri.fragment}';
  }

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
