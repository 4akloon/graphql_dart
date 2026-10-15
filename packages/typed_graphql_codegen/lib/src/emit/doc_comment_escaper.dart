/// Makes schema text safe inside a `///` comment.
///
/// `unintended_html_in_doc_comment` (in `package:lints`) reports an angle
/// bracket pair such as `List<User>` outside code, so the generated code would
/// fail its user's analysis. This wraps each such pair in backticks.
///
/// {@category codegen}
final class DocCommentEscaper {
  /// Creates the escaper.
  const DocCommentEscaper();

  /// [line] with every `<...>` outside a code span wrapped in backticks.
  String escape(String line) {
    if (!line.contains('<')) {
      return line;
    }
    final StringBuffer out = StringBuffer();
    bool isInCode = false;
    int index = 0;
    while (index < line.length) {
      final String character = line[index];
      if (character == '`') {
        isInCode = !isInCode;
      }
      final int end = isInCode || character != '<'
          ? -1
          : _closingBracket(line, index);
      if (end < 0) {
        out.write(character);
        index++;
      } else {
        out.write('`${line.substring(index, end + 1)}`');
        index = end + 1;
      }
    }
    return out.toString();
  }

  /// The index of the `>` that closes the `<` at [start], or -1 when the
  /// bracket opens no pair or holds a backtick (which would end the span).
  int _closingBracket(String line, int start) {
    int depth = 0;
    for (int index = start; index < line.length; index++) {
      final String character = line[index];
      if (character == '`') {
        return -1;
      }
      if (character == '<') {
        depth++;
      } else if (character == '>') {
        depth--;
        if (depth == 0) {
          return index;
        }
      }
    }
    return -1;
  }
}
