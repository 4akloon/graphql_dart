import 'package:typed_graphql/typed_graphql.dart';

import 'ast_json.dart';

/// The visitor of graphql-js's visitor suite: it records each call in
/// [visited] as `[label?, 'enter' or 'leave', kind, getValue(node)]`, with
/// graphql-js's `Kind` and `null` for `undefined`, and [enter] returns
/// what [decide] says.
class VisitRecorder extends AstVisitor {
  /// Creates a recorder that writes to [visited].
  VisitRecorder(this.visited, {this.label, this.decide});

  /// The calls, in order.
  final List<List<Object?>> visited;

  /// Written first in each entry, such as `'no-a'`; left out when null.
  final String? label;

  /// What [enter] returns for a node; [VisitAction.next] when null.
  final VisitAction Function(Node node)? decide;

  @override
  VisitAction enter(Node node) {
    visited.add(entry('enter', node));
    return decide?.call(node) ?? VisitAction.next;
  }

  @override
  void leave(Node node) => visited.add(entry('leave', node));

  /// One entry for [event] at [node].
  List<Object?> entry(String event, Node node) =>
      switch (const AstJson().of(node)) {
        final Map<String, Object?> json => [
          ?label,
          event,
          json['kind'],
          json['value'],
        ],
        _ => throw ArgumentError.value(node, 'node', 'has no AST JSON'),
      };
}
