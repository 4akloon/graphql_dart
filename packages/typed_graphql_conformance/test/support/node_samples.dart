import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'ast_json.dart';
import 'kitchen_sink.dart';

/// One parsed node of each graphql-js `Kind`, taken from the kitchen
/// sinks, a few values and types they lack, and the five schema
/// coordinates: what graphql-js's `filterNodes` builds from `{ kind }`.
final class NodeSamples {
  /// Creates the samples' builder; it keeps no state.
  const NodeSamples();

  static const Parser _parser = Parser(
    options: ParserOptions(allowDirectiveExtensions: true),
  );

  /// The first node of each kind, by graphql-js kind name, in kind order.
  Map<String, Node> byKind() {
    final found = <String, Node>{};
    final collector = _FirstOfEachKind(found);
    const walker = AstWalker();
    for (final text in [KitchenSink.query, KitchenSink.sdl]) {
      walker.walk(_document(text), collector);
    }
    walker.walk(_element(_parser.parseValue(Source('1.5'))), collector);
    walker.walk(_element(_parser.parseTypeRef(Source('[T!]'))), collector);
    for (final text in ['T', 'T.f', 'T.f(a:)', '@d', '@d(a:)']) {
      final coordinate = _parser.parseSchemaCoordinate(Source(text));
      walker.walk(_element(coordinate), collector);
    }
    final entries = found.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return Map.fromEntries(entries);
  }

  /// The kind names of [root] and every node under it.
  Set<String> kindsIn(Node root) {
    final found = <String, Node>{};
    const AstWalker().walk(root, _FirstOfEachKind(found));
    return found.keys.toSet();
  }

  Document _document(String text) => switch (_parser.parse(Source(text))) {
    ParseSuccess(:final document) => document,
    ParseFailure(:final diagnostics) => fail('$diagnostics'),
  };

  T _element<T extends Node>(ParseElementResult<T> result) => switch (result) {
    ParseElementSuccess(:final value) => value,
    ParseElementFailure(:final diagnostics) => fail('$diagnostics'),
  };
}

/// Records the first node of each kind it enters.
final class _FirstOfEachKind extends AstVisitor {
  _FirstOfEachKind(this.found);

  final Map<String, Node> found;

  @override
  VisitAction enter(Node node) {
    if (const AstJson().of(node) case {'kind': final String kind}) {
      found.putIfAbsent(kind, () => node);
    }
    return VisitAction.next;
  }
}
