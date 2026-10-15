import 'package:typed_graphql/typed_graphql.dart';

/// Where in a value coercion is: a chain of keys and indexes that shares
/// its parents, so a deep value costs one node per level and a path is
/// built only for a problem that is reported.
final class InputPath {
  const InputPath._(this._parent, this._segment);

  /// The path of the value itself.
  static const InputPath root = InputPath._(null, null);

  final InputPath? _parent;
  final PathSegment? _segment;

  /// The path of the field [name] of the object at this path.
  InputPath key(String name) => InputPath._(this, PathKey(name));

  /// The path of the item [position] of the list at this path.
  InputPath index(int position) => InputPath._(this, PathIndex(position));

  /// The segments from the root to here; no recursion, a path can be a
  /// thousand levels long.
  List<PathSegment> get segments {
    final reversed = <PathSegment>[];
    for (InputPath? at = this; at != null; at = at._parent) {
      if (at._segment case final segment?) {
        reversed.add(segment);
      }
    }
    return reversed.reversed.toList();
  }

  /// graphql-js's `printPathArray`: ` at .a[0].b`, empty for the root.
  String get description {
    final parts = segments;
    if (parts.isEmpty) {
      return '';
    }
    final text = StringBuffer(' at ');
    for (final part in parts) {
      switch (part) {
        case PathKey(:final name):
          text.write('.$name');
        case PathIndex(:final index):
          text.write('[$index]');
      }
    }
    return '$text';
  }
}
