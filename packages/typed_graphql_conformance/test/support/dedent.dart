/// graphql-js's `dedent` test tag: drops leading line breaks, trailing
/// blanks and the first line's indentation from every line.
final class Dedent {
  /// Creates the function; it keeps no state.
  const Dedent();

  static final RegExp _leadingBreaks = RegExp(r'^\n*');
  static final RegExp _trailingBlanks = RegExp(r'[ \t\n]*$');
  static final RegExp _indent = RegExp(r'^[ \t]*');

  /// [text] dedented, as `dedentString` does.
  String call(String text) {
    final trimmed = text
        .replaceFirst(_leadingBreaks, '')
        .replaceFirst(_trailingBlanks, '');
    final indent = _indent.stringMatch(trimmed) ?? '';
    final everyIndent = RegExp('^${RegExp.escape(indent)}', multiLine: true);
    return trimmed.replaceAll(everyIndent, '');
  }
}
