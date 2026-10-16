import 'dart:async';

/// A timer that fires only when a test says so.
final class ManualTimer implements Timer {
  ManualTimer(this.duration, this._callback, this._zone);

  /// How long the code asked to wait.
  final Duration duration;

  final void Function() _callback;
  final Zone _zone;
  bool _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => 0;

  @override
  void cancel() => _isActive = false;

  /// Runs the callback, as the clock reaching the deadline.
  void fire() {
    _isActive = false;
    _zone.run(_callback);
  }
}

/// Replaces the timers of the code a test runs with [ManualTimer]s, so a
/// test sees which are armed and cancelled without waiting for any clock.
///
/// Inside [run], `Future.delayed` is a manual timer as well: wait with
/// microtasks only.
final class ManualTimers {
  /// Every timer created so far.
  final List<ManualTimer> created = [];

  /// The timers that are armed.
  List<ManualTimer> get armed => [
    for (final timer in created)
      if (timer.isActive) timer,
  ];

  /// Runs [body] with the manual timers.
  Future<T> run<T>(Future<T> Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final timer = ManualTimer(duration, callback, zone);
        created.add(timer);
        return timer;
      },
    ),
  );

  /// Lets the microtasks that are queued run.
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.value();
    }
  }
}
