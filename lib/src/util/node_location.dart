class NodeLocation {
  final String name;
  final int index;

  NodeLocation(this.name, this.index);

  @override
  String toString() => 'NodeLocation(name: $name, index: $index}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeLocation &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          index == other.index;

  @override
  int get hashCode {
    var result = 1;
    result = 37 * result + name.hashCode;
    result = 37 * result + index.hashCode;
    return result;
  }
}
