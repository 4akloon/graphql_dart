import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

/// Checks [Node.withChildren] on one node and everything under it.
final class RebuildCheck {
  /// Creates the check.
  const RebuildCheck();

  /// Expects that [node] keeps itself for its own children, and that fresh
  /// names under it rebuild every node above them into an equivalent node
  /// of the same kind at the same place.
  void expectRebuilds(Node node) {
    expect(identical(node.withChildren(node.children), node), isTrue);
    final copy = _copy(node);
    expect(copy.runtimeType, node.runtimeType);
    expect(copy.isEquivalentTo(node), isTrue);
    expect((copy.start, copy.end), (node.start, node.end));
    for (final child in node.children) {
      expectRebuilds(child);
    }
  }

  /// [node] with a new instance of every [Name] under it.
  Node _copy(Node node) => switch (node) {
    Name(:final value, :final start, :final end) => Name(
      value,
      start: start,
      end: end,
    ),
    _ => node.withChildren([for (final child in node.children) _copy(child)]),
  };
}
