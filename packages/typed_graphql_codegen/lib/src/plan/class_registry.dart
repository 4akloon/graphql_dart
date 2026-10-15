import 'dart:collection';

import 'package:typed_graphql/typed_graphql.dart';

/// The nested classes planned so far in one run, so that two fields of one
/// type with the same selection nodes share one class.
///
/// Without it a field that every variant of a sealed class selects, but not
/// identically, would be planned again with its whole sub-tree for each
/// variant: the class count would grow with the depth to the power of the
/// variant count.
final class ClassRegistry {
  /// Creates an empty registry.
  ClassRegistry();

  final Map<Field, int> _ids = HashMap<Field, int>.identity();
  final Map<String, String> _classes = {};

  /// The class planned for the type named [typeName] and the field [nodes],
  /// compared by identity; null when there is none yet.
  String? classOf(String typeName, List<Field> nodes) =>
      _classes[_key(typeName, nodes)];

  /// Records that [className] is the class of [typeName] and [nodes].
  void record(String typeName, List<Field> nodes, String className) {
    _classes[_key(typeName, nodes)] = className;
  }

  String _key(String typeName, List<Field> nodes) => [
    typeName,
    for (final node in nodes) _ids.putIfAbsent(node, () => _ids.length),
  ].join(',');
}
