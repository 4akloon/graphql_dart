import 'dart:async';

/// The event source of the `ticks` subscription, which lets a test see
/// whether the server cancelled it.
final class TickSource {
  /// Creates a source that has not been listened to; an [isEndless] source
  /// sends the first tick and then waits, so only a cancel ends it.
  TickSource({this.isEndless = false});

  /// Whether the stream stops after its first tick without being done.
  final bool isEndless;

  /// Whether a listener cancelled the stream before it was done.
  bool isCancelled = false;

  /// A lazy stream of 1, 2 and 3, then done; nothing runs until it is
  /// listened to.
  Stream<int> stream() {
    late StreamController<int> controller; // Set below, read by onListen.
    controller = StreamController<int>(
      onListen: () {
        for (var tick = 1; tick <= (isEndless ? 1 : 3); tick++) {
          controller.add(tick);
        }
        if (!isEndless) controller.close();
      },
      onCancel: () => isCancelled = true,
    );
    return controller.stream;
  }
}
