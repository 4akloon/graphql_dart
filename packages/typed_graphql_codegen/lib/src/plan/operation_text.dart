import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:typed_graphql/typed_graphql.dart';

import 'root_typename.dart';
import 'typename_adder.dart';

/// Writes the document text an operation is sent with (R7.9): the operation
/// and every fragment it spreads, minified, with `__typename` added.
final class OperationText {
  /// Creates the writer for the project's [schema] and [fragments] by name.
  const OperationText(this.schema, this.fragments);

  /// The schema, which tells abstract types from object types.
  final Schema schema;

  /// The project's fragment definitions, by name.
  final Map<String, FragmentDefinition> fragments;

  RootTypename get _rootTypename =>
      RootTypename(schema, (name) => fragments[name]);

  /// The SHA-256 of a document [text], in lower-case hexadecimal.
  String hashOf(String text) => sha256.convert(utf8.encode(text)).toString();

  /// The minified text of [operation] followed by the fragments it spreads,
  /// directly or not, sorted by name.
  ///
  /// The operation's own selection set gets `__typename` when it reads the
  /// type of an abstract selection; a subscription cannot select it and is
  /// left as written.
  String of(OperationDefinition operation) {
    const adder = TypenameAdder();
    final OperationDefinition root = _withRootTypename(operation, adder);
    final document = Document([root, ..._spread(operation)]);
    final Node transformed = adder.transform(document) ?? document;
    return const Printer(isMinified: true).print(transformed);
  }

  List<FragmentDefinition> _spread(OperationDefinition operation) {
    final visited = <String>{};
    final found = <FragmentDefinition>[];
    final pending = _spreadNames(operation);
    while (pending.isNotEmpty) {
      final String name = pending.removeLast();
      final FragmentDefinition? fragment = fragments[name];
      if (fragment == null || !visited.add(name)) continue;
      found.add(fragment);
      pending.addAll(_spreadNames(fragment));
    }
    return found..sort((a, b) => a.name.value.compareTo(b.name.value));
  }

  List<String> _spreadNames(Node definition) {
    final collector = _SpreadCollector();
    const AstWalker().walk(definition, collector);
    return collector.names;
  }

  OperationDefinition _withRootTypename(
    OperationDefinition operation,
    TypenameAdder adder,
  ) {
    if (operation.operation == OperationType.subscription ||
        !_rootTypename.isNeededBy(operation.selectionSet)) {
      return operation;
    }
    return OperationDefinition(
      operation.operation,
      adder.appendTo(operation.selectionSet),
      description: operation.description,
      name: operation.name,
      variableDefinitions: operation.variableDefinitions,
      directives: operation.directives,
      start: operation.start,
      end: operation.end,
    );
  }
}

// Collects the names of the fragments a definition spreads.
final class _SpreadCollector extends AstVisitor {
  final List<String> names = [];

  @override
  VisitAction enter(Node node) {
    if (node is FragmentSpread) names.add(node.name.value);
    return VisitAction.next;
  }
}
