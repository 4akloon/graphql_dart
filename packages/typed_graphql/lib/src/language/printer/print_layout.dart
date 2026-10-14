/// graphql-js's printer combinators, so printed text matches it to the
/// character: joining that skips empty parts, wrapping, indentation,
/// blocks and the 80-column rule for argument lists.
final class PrintLayout {
  /// Creates the combinators; they keep no state.
  const PrintLayout();

  /// The longest argument list or list value kept on one line.
  static const int maxLineLength = 80;

  /// The non-empty [parts] joined with [separator].
  String join(Iterable<String> parts, [String separator = '']) =>
      parts.where((part) => part.isNotEmpty).join(separator);

  /// [text] between [start] and [end], or `''` when [text] is null or
  /// empty.
  String wrap(String start, String? text, [String end = '']) =>
      text == null || text.isEmpty ? '' : '$start$text$end';

  /// [text] with every line indented by two spaces.
  String indent(String text) => wrap('  ', text.replaceAll('\n', '\n  '));

  /// [items] one per line, indented, between braces; `''` for none.
  String block(Iterable<String> items) =>
      wrap('{\n', indent(join(items, '\n')), '\n}');

  /// Whether any of [items] spans several lines.
  bool hasMultilineItems(Iterable<String> items) =>
      items.any((item) => item.contains('\n'));

  /// [prefix] and its [arguments] in parentheses, one per line when the
  /// line would pass [maxLineLength].
  String withArguments(String prefix, List<String> arguments) {
    final line = prefix + wrap('(', join(arguments, ', '), ')');
    if (line.length <= maxLineLength) {
      return line;
    }
    return prefix + wrap('(\n', indent(join(arguments, '\n')), '\n)');
  }

  /// An `ArgumentsDefinition`: one per line when any of [arguments]
  /// spans several lines, such as one with a description.
  String argumentDefinitions(List<String> arguments) =>
      hasMultilineItems(arguments)
      ? wrap('(\n', indent(join(arguments, '\n')), '\n)')
      : wrap('(', join(arguments, ', '), ')');
}
