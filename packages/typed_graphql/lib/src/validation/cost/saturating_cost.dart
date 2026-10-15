import 'dart:math';

/// Sums and products of costs that stay finite.
///
/// A cost can exceed what a double holds (a 400-digit `Int` literal is
/// `Infinity`), and `0 * Infinity` or `Infinity - Infinity` is NaN, which no
/// comparison with a maximum catches. These operations clamp to the finite
/// range and make a product with 0 equal 0, so a cost is never NaN or
/// infinite and an excess stays an excess (R0.3, R3.8).
extension SaturatingCost on double {
  /// The sum of this and [other], clamped to the finite range.
  double plus(double other) => _clamp(this + other);

  /// The product of this and [other], clamped to the finite range; 0 when
  /// either is 0.
  double times(double other) {
    if (this == 0 || other == 0) {
      return 0;
    }
    return _clamp(this * other);
  }

  double _clamp(double value) =>
      max<double>(-double.maxFinite, min<double>(double.maxFinite, value));
}
