import 'node_location.dart';

abstract interface class NodeAdapter<T> {
  Map<String, List<T>> getNamedChildren(T node);

  T withNewChildren(T node, Map<String, List<T>> newChildren);

  T removeChild(T node, NodeLocation location);
}
