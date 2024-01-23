import 'node.dart';

class NodeChildrenContainer {
  final Map<String, List<Node>> _children = <String, List<Node>>{};

  NodeChildrenContainer._(Map<String, List<Node>> children) {
    _children.addAll(children);
  }

  List<T> getChildrenValue<T extends Node<dynamic>>(String key) {
    if (!_children.containsKey(key)) {
      return <T>[];
    } else {
      return _children[key]!.cast<T>();
    }
  }

  T? getChild<T extends Node<dynamic>>(String key) {
    final List<T> children = getChildrenValue<T>(key);

    if (children.length > 1) {
      throw Exception('More than one child found for key $key');
    } else if (children.isNotEmpty) {
      return children.first;
    } else {
      return null;
    }
  }

  Map<String, List<Node>> get children => _children;

  static NodeChildrenContainerBuilder builder() =>
      NodeChildrenContainerBuilder._();

  static NodeChildrenContainerBuilder builderFromChildren(
          Map<String, List<Node>> children) =>
      NodeChildrenContainerBuilder._(children);

  static NodeChildrenContainerBuilder builderFromContainer(
          NodeChildrenContainer container) =>
      NodeChildrenContainerBuilder.fromContainer(container);

  bool get isEmpty => _children.isEmpty;
}

class NodeChildrenContainerBuilder {
  final Map<String, List<Node>> _children = <String, List<Node>>{};

  NodeChildrenContainerBuilder._([Map<String, List<Node>>? children]) {
    if (children != null) {
      _children.addAll(children);
    }
  }

  NodeChildrenContainerBuilder.fromContainer(NodeChildrenContainer container) {
    _children.addAll(container._children);
  }

  NodeChildrenContainerBuilder child(String key, Node? child) {
    if (child == null) {
      return this;
    }
    if (!_children.containsKey(key)) {
      _children[key] = <Node>[];
    }

    _children[key]!.add(child);

    return this;
  }

  NodeChildrenContainerBuilder children(String key, List<Node> children) {
    if (!_children.containsKey(key)) {
      _children[key] = <Node>[];
    }

    _children[key]!.addAll(children);

    return this;
  }

  NodeChildrenContainerBuilder replaceChild(String key, int index, Node child) {
    if (!_children.containsKey(key)) {
      _children[key] = <Node>[];
    }

    _children[key]![index] = child;

    return this;
  }

  NodeChildrenContainerBuilder removeChild(String key, int index) {
    if (!_children.containsKey(key)) {
      _children[key] = <Node>[];
    }

    _children[key]!.removeAt(index);

    return this;
  }

  NodeChildrenContainer build() => NodeChildrenContainer._(_children);
}
