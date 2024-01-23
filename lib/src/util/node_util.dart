import 'package:collection/collection.dart';
import 'package:graphql_dart/src/util/fp_kit.dart';

import '../language/named_node.dart';
import '../language/node.dart';
import '../language/node_children_container.dart';
import 'node_location.dart';

class NodeUtil {
  static T? findNodeByName<T extends NamedNode<T>>(List<T> nodes, String name) {
    return nodes.firstWhereOrNull((node) => node.name == name);
  }

  static Map<String, T> nodeByName<T extends NamedNode<T>>(List<T> nameNode) {
    return FpKit.getByName<T>(nameNode, (node) => node.name, (p0, p1) => p0);
  }

  static void assertNewChildrenAreEmpty(NodeChildrenContainer newChildren) {
    assert(newChildren.children.isEmpty, 'New children must be empty');
  }

  static Node removeChild(Node node, NodeLocation childLocationToRemove) {
    final namedChildren = node.namedChildren;
    final newChildren = namedChildren.transform(
      (builder) => builder.removeChild(
        childLocationToRemove.name,
        childLocationToRemove.index,
      ),
    );
    return node.withNewChildren(newChildren) as Node;
  }
}
