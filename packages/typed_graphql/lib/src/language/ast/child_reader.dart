import 'node.dart';

/// Reads the list given to [Node.withChildren] back into a node's fields,
/// in grammar order, for [Node.rebuildFrom].
///
/// Each read consumes children from the front: [one] a required child,
/// [optional] a child that may be absent, [all] the run of children of one
/// kind. A child that does not fit is a [StateError]: [Node.withChildren]
/// is called by code, never with user input.
final class ChildReader(final List<Node> children) {
  /// Creates a reader positioned before the first of [children].
  this;

  int _next = 0;

  /// [node] when [children] are identical to its own; otherwise the node
  /// [build] makes from this reader, which must consume every child.
  T rebuild<T extends Node>(T node, T Function(ChildReader read) build) {
    if (_isUnchanged(node.children)) {
      return node;
    }
    final rebuilt = build(this);
    if (_next != children.length) {
      throw StateError(
        'Too many children for ${node.runtimeType}: '
        '${children.length - _next} left over.',
      );
    }
    return rebuilt;
  }

  /// The next child, which must be a [T].
  T one<T extends Node>() =>
      optional<T>() ??
      (throw StateError('Expected a $T child at position $_next.'));

  /// The next child when it is a [T]; null, consuming nothing, otherwise.
  T? optional<T extends Node>() {
    if (_next == children.length) {
      return null;
    }
    if (children[_next] case final T child) {
      _next++;
      return child;
    }
    return null;
  }

  /// The children from here on that are a [T], up to the first that is
  /// not; empty when the next child is not a [T].
  List<T> all<T extends Node>() => [
    for (var child = optional<T>(); child != null; child = optional<T>()) child,
  ];

  bool _isUnchanged(List<Node> original) {
    if (original.length != children.length) {
      return false;
    }
    for (var i = 0; i < original.length; i++) {
      if (!identical(original[i], children[i])) {
        return false;
      }
    }
    return true;
  }
}
