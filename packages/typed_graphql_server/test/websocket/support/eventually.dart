import 'dart:async';

/// Waits until a condition holds, polling every few milliseconds; fails the
/// test after [limit] instead of guessing how long the work takes.
final class Eventually {
  const Eventually({this.limit = const Duration(seconds: 10)});

  final Duration limit;

  Future<void> call(bool Function() condition) async {
    final deadline = DateTime.now().add(limit);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('The condition never held', limit);
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

/// The default wait.
const Eventually eventually = Eventually();
