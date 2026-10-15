import 'package:typed_graphql/typed_graphql.dart';

/// The response path of a field: response names and list indexes from the
/// root of `data`. Extending a path costs one object, so the executor builds
/// one per field without copying; [toList] makes the list an error needs.
///
/// {@category execution}
final class ResponsePath {
  const ResponsePath._(this._parent, this._segment, this.length);

  /// The empty path, the root of `data`.
  static const ResponsePath root = ResponsePath._(null, null, 0);

  final ResponsePath? _parent;
  final PathSegment? _segment;

  /// How many segments the path has.
  final int length;

  /// This path followed by the response name [name].
  ResponsePath key(String name) =>
      ResponsePath._(this, PathKey(name), length + 1);

  /// This path followed by the list index [position].
  ResponsePath index(int position) =>
      ResponsePath._(this, PathIndex(position), length + 1);

  /// The segments from the root.
  List<PathSegment> toList() {
    final segments = <PathSegment>[];
    for (ResponsePath? step = this; step != null; step = step._parent) {
      if (step._segment case final segment?) {
        segments.add(segment);
      }
    }
    return segments.reversed.toList(growable: false);
  }

  @override
  String toString() => toList().join('.');
}
