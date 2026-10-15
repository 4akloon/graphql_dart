import 'dart:math';

/// The nodes of a directed graph that lie on a cycle, found with Tarjan's
/// algorithm over an explicit stack, so a chain of 100000 fragments cannot
/// overflow the call stack on the web. Linear in the nodes and edges.
final class StronglyConnectedComponents(
  /// The targets of the edges of each node; every target is also a key.
  final Map<String, Set<String>> edges,
) {
  /// Creates the search over [edges].
  this;

  final Map<String, int> _order = {};
  final Map<String, int> _low = {};
  final List<String> _open = [];
  final Set<String> _onStack = {};
  final Set<String> _cyclic = {};

  /// The nodes in a component of two or more nodes, or with an edge to
  /// themselves.
  Set<String> cyclicNodes() {
    for (final root in edges.keys) {
      if (!_order.containsKey(root)) {
        _visit(root);
      }
    }
    return _cyclic;
  }

  void _visit(String root) {
    final calls = [_Call(root, edges[root]!.iterator)];
    _enter(root);
    while (calls.isNotEmpty) {
      final call = calls.last;
      if (call.targets.moveNext()) {
        final target = call.targets.current;
        if (!_order.containsKey(target)) {
          _enter(target);
          calls.add(_Call(target, edges[target]!.iterator));
        } else if (_onStack.contains(target)) {
          _lower(call.name, _order[target]!);
        }
        continue;
      }
      calls.removeLast();
      _leave(call.name);
      if (calls.isNotEmpty) {
        _lower(calls.last.name, _low[call.name]!);
      }
    }
  }

  void _enter(String name) {
    _order[name] = _low[name] = _order.length;
    _open.add(name);
    _onStack.add(name);
  }

  void _lower(String name, int order) {
    _low[name] = min(_low[name]!, order);
  }

  // A node whose low link is its own order is the root of a component.
  void _leave(String name) {
    if (_low[name] != _order[name]) return;
    final component = <String>[];
    String member;
    do {
      member = _open.removeLast();
      _onStack.remove(member);
      component.add(member);
    } while (member != name);
    if (component.length > 1 || edges[name]!.contains(name)) {
      _cyclic.addAll(component);
    }
  }
}

final class _Call(final String name, final Iterator<String> targets);
