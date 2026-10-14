/// Unwinds the parser from a syntax error, already reported, to the
/// nearest recovery point: the selection or the definition being parsed.
///
/// It never leaves the parser (R0.3): `Parser` catches it and turns the
/// sink into a result.
final class SyntaxAbort implements Exception {
  /// Creates an abort; [endsDefinition] skips the selection recovery.
  const SyntaxAbort({this.endsDefinition = false});

  /// Whether the whole definition is dropped, as after a depth error.
  final bool endsDefinition;
}
