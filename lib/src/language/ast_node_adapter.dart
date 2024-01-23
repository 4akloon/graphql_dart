import '../util/node_adapter.dart';
import '../util/node_location.dart';
import '../util/node_util.dart';
import 'node.dart';
import 'node_children_container.dart';

class AstNodeAdapter implements NodeAdapter<Node> {
  static final astNodeAdapter = AstNodeAdapter._();

  AstNodeAdapter._();

  @override
  Map<String, List<Node>> getNamedChildren(Node node) {
    return node.namedChildren.children;
  }

  @override
  Node withNewChildren(Node node, Map<String, List<Node>> newChildren) {
    final nodeChildrenContainer =
        NodeChildrenContainer.builderFromChildren(newChildren).build();

    return node.withNewChildren(nodeChildrenContainer) as Node;
  }

  @override
  Node removeChild(Node node, NodeLocation location) {
    return NodeUtil.removeChild(node, location);
  }
}
