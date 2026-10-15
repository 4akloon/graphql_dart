import 'dart:async';

/// graphql-js's `SimplePubSub`: a mock of a pub/sub system whose subscribers
/// are streams.
///
/// A subscriber exists from the call of [getSubscriber] until its stream is
/// cancelled, whether or not anybody listens yet: events emitted before the
/// first listener are kept for it, as graphql-js's push queue keeps them.
/// `transform` runs at [emit], not at delivery.
final class SimplePubSub<T> {
  /// Creates a pub/sub without subscribers.
  SimplePubSub();

  final Set<void Function(T event)> _subscribers = {};

  /// Hands [event] to every subscriber; whether there was one.
  bool emit(T event) {
    for (final subscriber in _subscribers.toList()) {
      subscriber(event);
    }
    return _subscribers.isNotEmpty;
  }

  /// A single-subscription stream of the events emitted from now on, each
  /// passed through [transform]; cancelling it ends the subscription.
  Stream<R> getSubscriber<R>(R Function(T event) transform) {
    // late: assigned right below, before any event can reach [push].
    late final StreamController<R> controller;
    void push(T event) => controller.add(transform(event));
    controller = StreamController<R>(
      onCancel: () {
        _subscribers.remove(push);
        return controller.close();
      },
    );
    _subscribers.add(push);
    return controller.stream;
  }
}
