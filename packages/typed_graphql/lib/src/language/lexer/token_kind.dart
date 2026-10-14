/// The kinds of lexical tokens (spec §2.1.6), plus [comment], [error] and
/// [eof].
enum TokenKind(
  /// How a message names the kind, as graphql-js does: a punctuator in
  /// quotes, such as `"{"`, other kinds by name, such as `Name`.
  final String description,
) {
  /// `!`.
  bang('"!"'),

  /// `$`.
  dollar(r'"$"'),

  /// `&`.
  ampersand('"&"'),

  /// `(`.
  parenLeft('"("'),

  /// `)`.
  parenRight('")"'),

  /// `...`.
  spread('"..."'),

  /// `:`.
  colon('":"'),

  /// `=`.
  equals('"="'),

  /// `@`.
  at('"@"'),

  /// `[`.
  bracketLeft('"["'),

  /// `]`.
  bracketRight('"]"'),

  /// `{`.
  braceLeft('"{"'),

  /// `|`.
  pipe('"|"'),

  /// `}`.
  braceRight('"}"'),

  /// A name or a keyword.
  name('Name'),

  /// An integer literal.
  int('Int'),

  /// A float literal.
  float('Float'),

  /// A quoted string.
  string('String'),

  /// A block string, `"""..."""`.
  blockString('BlockString'),

  /// A comment, produced only when the lexer keeps comments.
  comment('Comment'),

  /// Text that is not a token; the lexer reported a diagnostic for it.
  error('Error'),

  /// The end of the document.
  eof('<EOF>');

  /// Whether this kind is a punctuator, such as `{` or `...`.
  bool get isPunctuator => index <= braceRight.index;
}
