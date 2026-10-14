import 'markdown_fence.dart';

/// A complete Dart program in a guide, and the output the guide says it
/// prints.
final class DocSnippet(
  /// The Markdown file, from the package folder.
  final String file,

  /// The 1-based line of the snippet's opening fence.
  final int line,

  /// The program.
  final String code,

  /// What the guide says the program prints; null when it says nothing.
  final String? expectedOutput,
) {
  /// Creates a snippet.
  this;

  /// `file:line`, the place to look when the snippet fails.
  String get place => '$file:$line';
}

/// Finds the programs in a Markdown file.
///
/// Every fence tagged `dart` is a program: complete, with its imports and
/// `main`. A fence tagged `text` right after it, introduced by the line
/// `It prints:`, is its expected output. What is not a program, such as a
/// signature or a fragment, is written in a fence tagged `text`, or with
/// no tag.
final class DocSnippets {
  /// Creates the finder.
  const DocSnippets();

  /// The snippets of [markdown], the content of [file]. An output with no
  /// program before it, and a fence tagged `dart` plus anything else, and
  /// an `It prints:` followed by a fence not tagged `text`, are a
  /// [FormatException].
  List<DocSnippet> of(String file, String markdown) {
    final fences = const MarkdownFences().of(markdown);
    final snippets = <DocSnippet>[];
    for (final (index, fence) in fences.indexed) {
      if (fence.info.startsWith('dart') && fence.info != 'dart') {
        throw FormatException('$file:${fence.line}: tag "${fence.info}"');
      }
      if (_isOutput(fence) &&
          (index == 0 || fences[index - 1].info != 'dart')) {
        throw FormatException('$file:${fence.line}: output without a program');
      }
      if (fence.info != 'text' && fence.precedingText.endsWith(_outputIntro)) {
        throw FormatException(
          '$file:${fence.line}: "$_outputIntro" must be followed by a text '
          'fence, not "${fence.info}"',
        );
      }
      if (fence.info == 'dart') {
        snippets.add(
          DocSnippet(
            file,
            fence.line,
            fence.body,
            index + 1 < fences.length && _isOutput(fences[index + 1])
                ? fences[index + 1].body
                : null,
          ),
        );
      }
    }
    return snippets;
  }

  static const String _outputIntro = 'It prints:';

  bool _isOutput(MarkdownFence fence) =>
      fence.info == 'text' && fence.precedingText.endsWith(_outputIntro);
}
