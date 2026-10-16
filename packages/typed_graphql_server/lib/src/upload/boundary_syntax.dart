import 'package:meta/meta.dart';

/// The boundaries RFC 2046 section 5.1.1 allows: one to 70 `bchars`, the
/// last one not a space.
///
/// `package:mime` reads a boundary by code units cut to a byte, so only the
/// ASCII of the grammar is safe to hand to it and to the header scanner.
@internal
final class BoundarySyntax {
  /// Creates the rule.
  const BoundarySyntax();

  static final RegExp _boundary = RegExp(
    r"^[0-9A-Za-z'()+_,\-./:=? ]{0,69}[0-9A-Za-z'()+_,\-./:=?]$",
  );

  /// Whether [boundary] is a boundary of RFC 2046.
  bool allows(String boundary) => _boundary.hasMatch(boundary);
}
