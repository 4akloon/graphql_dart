import 'dart:math';

/// How long to wait before a retry or a reconnection: exponential growth
/// with "full jitter", a uniform draw between zero and the ceiling, so
/// that many clients that failed together do not retry together (R8.4).
///
/// The ceiling of retry `n` (from 0) is [initialDelay] times [multiplier]
/// to the power `n`, at most [maxDelay].
///
/// {@category link}
final class const Backoff({
  /// The ceiling of the first retry.
  final Duration initialDelay = const Duration(milliseconds: 300),

  /// The highest ceiling.
  final Duration maxDelay = const Duration(seconds: 30),

  /// How much the ceiling grows from one retry to the next.
  final double multiplier = 2,
}) {
  /// Creates a backoff.
  this;

  /// The longest wait before retry [retry] (from 0).
  Duration ceilingFor(int retry) {
    final max = maxDelay.inMicroseconds;
    var ceiling = initialDelay.inMicroseconds.toDouble();
    for (var step = 0; step < retry && ceiling < max; step++) {
      ceiling *= multiplier;
    }
    return Duration(microseconds: min(ceiling, max.toDouble()).round());
  }

  /// The wait before retry [retry] (from 0), drawn with [random].
  Duration delayFor(int retry, Random random) => Duration(
    microseconds: (random.nextDouble() * ceilingFor(retry).inMicroseconds)
        .floor(),
  );
}
