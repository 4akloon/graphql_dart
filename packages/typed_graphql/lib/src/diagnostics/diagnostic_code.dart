/// The catalog of diagnostic codes: one value per problem, each with a
/// stable [id] and a doc comment that says when it is reported.
///
/// An id is `GQL` and three digits; the hundreds digit is the area:
///
/// | Ids | Area | Codes added by |
/// |---|---|---|
/// | `GQL0xx` | lexer and syntax | M2 |
/// | `GQL1xx` | type system: building and validating a schema | M3 |
/// | `GQL2xx` | operation validation (the doc comment names the spec rule) | M4 |
/// | `GQL3xx` | coercion and execution | M5 |
/// | `GQL4xx` | transports and protocols | M6, M7 |
/// | `GQL5xx` | code generation | M8, M10 |
///
/// `GQL000` belongs to no area: any sink reports it when its limit is
/// reached. Values are sorted by [id]. An id is public API: it is never
/// renumbered, reused or removed. Stages add codes in minor versions, so do
/// not switch over this enum exhaustively: match the codes you handle and
/// add a wildcard case.
enum DiagnosticCode(
  /// The stable id, such as `GQL000`, shown in messages and documentation.
  final String id,
) {
  /// `GQL000`: a sink kept as many errors as its limit allows and dropped
  /// the rest. It is reported once, at the place of the first dropped
  /// error; the run behind the sink should stop.
  diagnosticLimitReached('GQL000'),

  /// `GQL001`: a character that starts no token, such as `~`, a single
  /// quote or `..`.
  unexpectedCharacter('GQL001'),

  /// `GQL002`: a code unit that is not part of a Unicode scalar value: a
  /// surrogate without its pair, in or outside a string (spec §2.1.1).
  invalidCharacter('GQL002'),

  /// `GQL003`: a malformed number, such as `007`, `1.`, `.5`, `1e` or a
  /// name glued to a number (`1a`).
  invalidNumber('GQL003'),

  /// `GQL004`: a string or block string without its closing quotes; a
  /// quoted string also ends at a line break.
  unterminatedString('GQL004'),

  /// `GQL005`: an escape sequence that is not `\"`, `\\`, `\/`, `\b`,
  /// `\f`, `\n`, `\r`, `\t` or a Unicode escape of a scalar value.
  invalidEscapeSequence('GQL005'),

  /// `GQL006`: a document with more tokens than the limit; the rest is not
  /// read.
  tokenLimitExceeded('GQL006');
}
