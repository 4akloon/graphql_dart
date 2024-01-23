import 'node_location.dart';

class Breadcrumb<T> {
  final T node;
  final NodeLocation location;

  Breadcrumb(this.node, this.location);

  @override
  String toString() => 'Breadcrumb(node: $node, location: $location)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Breadcrumb &&
          runtimeType == other.runtimeType &&
          node == other.node &&
          location == other.location;

  @override
  int get hashCode {
    var result = 1;
    result = 37 * result + node.hashCode;
    result = 37 * result + location.hashCode;
    return result;
  }
}
