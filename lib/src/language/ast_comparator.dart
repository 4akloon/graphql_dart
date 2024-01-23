import 'node.dart';
import 'value.dart';

class AstComparator {
  AstComparator._();

  static bool sameValue(Value? value1, Value? value2) {
    if (value1 == null && value2 == null) {
      return true;
    } else if (value1 == null || value2 == null) {
      return false;
    } else {
      return value1.isEqualTo(value2);
    }
  }

  static bool isEqual(Node? node1, Node? node2) {
    if (node1 == null || node2 == null) {
      return node1 == node2;
    } else if (!node1.isEqualTo(node2)) {
      return false;
    }

    final List<Node> childs1 = node1.children;
    final List<Node> childs2 = node2.children;

    if (childs1.length != childs2.length) {
      return false;
    }

    for (int i = 0; i < childs1.length; i++) {
      if (!isEqual(childs1[i], childs2[i])) {
        return false;
      }
    }
    return true;
  }

  static bool isEqualList(List<Node> list1, List<Node> list2) {
    if (list1.length != list2.length) {
      return false;
    }

    for (int i = 0; i < list1.length; i++) {
      if (!isEqual(list1[i], list2[i])) {
        return false;
      }
    }
    return true;
  }
}
