/// The character classes of the lexical grammar (spec §2.1), over UTF-16
/// code units; -1 stands for the end of the document and is in no class.
final class CharacterClass {
  /// Creates the classes; they keep no state.
  const CharacterClass();

  /// Whether [unit] is `0`–`9`.
  bool isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

  /// Whether [unit] is a letter `A`–`Z` or `a`–`z`.
  bool isLetter(int unit) =>
      (unit >= 0x41 && unit <= 0x5a) || (unit >= 0x61 && unit <= 0x7a);

  /// Whether [unit] may start a name: a letter or `_`.
  bool isNameStart(int unit) => isLetter(unit) || unit == 0x5f;

  /// Whether [unit] may continue a name: a letter, a digit or `_`.
  bool isNameContinue(int unit) => isNameStart(unit) || isDigit(unit);

  /// Whether [point] is a Unicode scalar value: a code point that is not
  /// a surrogate.
  bool isScalarValue(int point) =>
      (point >= 0 && point <= 0xd7ff) || (point >= 0xe000 && point <= 0x10ffff);

  /// Whether [unit] is the first half of a surrogate pair.
  bool isLeadingSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;

  /// Whether [unit] is the second half of a surrogate pair.
  bool isTrailingSurrogate(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

  /// The value of the hexadecimal digit [unit], or -1 when it is none.
  int hexValue(int unit) => switch (unit) {
    >= 0x30 && <= 0x39 => unit - 0x30,
    >= 0x41 && <= 0x46 => unit - 0x37,
    >= 0x61 && <= 0x66 => unit - 0x57,
    _ => -1,
  };
}
