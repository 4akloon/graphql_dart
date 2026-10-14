/// Finds the nodes of a graph that lie on a cycle, in time linear in the
/// size of the part of the graph reachable from the roots: Tarjan's
/// strongly connected components, with its own stack so a long chain of
/// references cannot overflow the call stack.
///
/// A node is on a cycle when its component has another node, or when it
/// has an edge to itself.
final class CycleFinder(
  /// The nodes a node points to; called once per reached node.
  final List<String> Function(String node) edgesOf,
) {
  /// Creates a finder for the graph [edgesOf] describes.
  this;

  /// The nodes on a cycle among those reachable from [roots].
  Set<String> cyclicAmong(Iterable<String> roots) {
    final run = _Run(edgesOf);
    for (final root in roots) {
      run.visit(root);
    }
    return run.cyclic;
  }
}

// One search: the numbering of the nodes and the components found.
final class _Run(final List<String> Function(String node) edgesOf) {
  this;

  final Set<String> cyclic = {};
  final Map<String, int> _numbers = {};
  final Map<String, int> _lowest = {};
  final List<String> _open = [];
  final Set<String> _isOpen = {};
  final List<_Frame> _frames = [];

  void visit(String root) {
    if (_numbers.containsKey(root)) {
      return;
    }
    _enter(root);
    while (_frames.isNotEmpty) {
      final frame = _frames.last;
      if (frame.next < frame.edges.length) {
        _follow(frame, frame.edges[frame.next++]);
      } else {
        _frames.removeLast();
        _leave(frame.node);
      }
    }
  }

  void _enter(String node) {
    _numbers[node] = _lowest[node] = _numbers.length;
    _open.add(node);
    _isOpen.add(node);
    _frames.add(_Frame(node, edgesOf(node)));
  }

  void _follow(_Frame frame, String target) {
    if (target == frame.node) {
      cyclic.add(target);
    }
    if (!_numbers.containsKey(target)) {
      _enter(target);
    } else if (_isOpen.contains(target)) {
      _lowest[frame.node] = _min(_lowest[frame.node]!, _numbers[target]!);
    }
  }

  // The node is finished: it closes a component when no open node below
  // it was reached, and tells its parent how low it reached.
  void _leave(String node) {
    if (_lowest[node] == _numbers[node]) {
      _closeComponent(node);
    }
    if (_frames.isNotEmpty) {
      final parent = _frames.last.node;
      _lowest[parent] = _min(_lowest[parent]!, _lowest[node]!);
    }
  }

  void _closeComponent(String root) {
    final component = <String>[];
    String node;
    do {
      node = _open.removeLast();
      _isOpen.remove(node);
      component.add(node);
    } while (node != root);
    if (component.length > 1) {
      cyclic.addAll(component);
    }
  }

  static int _min(int a, int b) => a < b ? a : b;
}

// A node being searched and the position of its next edge.
final class _Frame(final String node, final List<String> edges) {
  this;

  int next = 0;
}
