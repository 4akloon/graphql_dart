import 'package:meta/meta.dart';

import 'token_kind.dart';

/// One lexical token: its [kind], its offsets and, for names, numbers and
/// strings, its [value].
@immutable
final class const Token(
  /// The kind of token.
  final TokenKind kind,

  /// The offset of the first code unit, in UTF-16 code units.
  final int start,

  /// The offset after the last code unit.
  final int end, {

  /// The name, the raw number lexeme, the decoded string or the comment
  /// text without `#`; null for punctuators, errors and the end.
  final String? value,
}) {
  /// Creates a token.
  this;

  /// How a message names this token: its kind, then its value in quotes,
  /// such as `Name "id"` (graphql-js's `getTokenDesc`).
  String get description =>
      value == null ? kind.description : '${kind.description} "$value"';

  @override
  String toString() => '$description@$start:$end';
}
