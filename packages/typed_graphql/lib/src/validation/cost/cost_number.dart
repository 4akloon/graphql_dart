/// A cost as the messages print it.
final class CostNumber(double value) {
  /// Creates the printable form of [value].
  this;

  // -0.0 prints as "-0" on the VM and "0" on JavaScript: normalised.
  /// The cost, with a negative zero turned into zero.
  final double value = value == 0 ? 0.0 : value;

  // Beyond 1e15 the platforms print doubles differently (the VM
  // `1.152921504606847e+18`, JavaScript `1152921504606847000`); the
  // exponential form is the same everywhere.
  static const double _largest = 1000000000000000;

  /// `1200` for an integral value below 1e15, `2.5` for a fraction,
  /// `1.152921504606847e+18` from 1e15 on, `Infinity` for an infinity: the
  /// same text on every platform.
  String get text => switch (value) {
    final number when !number.isFinite => number.toString(),
    final number when number.abs() >= _largest =>
      number.toStringAsExponential(),
    final number when number == number.truncateToDouble() =>
      number.toStringAsFixed(0),
    final number => number.toString(),
  };
}
