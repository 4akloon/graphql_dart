import 'dart:math';

import 'package:test/test.dart';
import 'package:typed_graphql_client/typed_graphql_client.dart';

/// A random source that always draws [value].
final class FixedRandom implements Random {
  const FixedRandom(this.value);

  final double value;

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => (value * max).floor();

  @override
  bool nextBool() => value >= 0.5;
}

void main() {
  const backoff = Backoff();

  test('the ceiling starts at the initial delay', () {
    expect(backoff.ceilingFor(0), const Duration(milliseconds: 300));
  });

  test('the ceiling grows by the multiplier', () {
    expect(backoff.ceilingFor(1), const Duration(milliseconds: 600));
    expect(backoff.ceilingFor(3), const Duration(milliseconds: 2400));
  });

  test('the ceiling stops at the maximum', () {
    expect(backoff.ceilingFor(20), const Duration(seconds: 30));
  });

  test('a huge retry number neither overflows nor loops long', () {
    expect(backoff.ceilingFor(1 << 40), const Duration(seconds: 30));
  });

  test('the delay is the draw times the ceiling', () {
    expect(
      backoff.delayFor(1, const FixedRandom(0.5)),
      const Duration(milliseconds: 300),
    );
  });

  test('the delay is never above the ceiling', () {
    final random = Random(7);
    for (var retry = 0; retry < 12; retry++) {
      final delay = backoff.delayFor(retry, random);
      expect(delay, lessThanOrEqualTo(backoff.ceilingFor(retry)));
      expect(delay, greaterThanOrEqualTo(Duration.zero));
    }
  });

  test('custom settings apply', () {
    const custom = Backoff(
      initialDelay: Duration(seconds: 1),
      maxDelay: Duration(seconds: 5),
      multiplier: 3,
    );
    expect(custom.ceilingFor(1), const Duration(seconds: 3));
    expect(custom.ceilingFor(2), const Duration(seconds: 5));
  });
}
