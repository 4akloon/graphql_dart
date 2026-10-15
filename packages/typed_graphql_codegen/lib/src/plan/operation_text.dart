import 'package:typed_graphql/typed_graphql.dart';

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
        !_readsAbstractType(operation.selectionSet)) {
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

  // Whether the top level of [root] spreads a fragment, or has an inline
  // fragment, on an abstract type, through spread fragments too.
  bool _readsAbstractType(SelectionSet root) {
    final visited = <String>{};
    final pending = [...root.selections];
    while (pending.isNotEmpty) {
      switch (pending.removeLast()) {
        case Field():
          continue;
        case InlineFragment(:final typeCondition, :final selectionSet):
          if (_isAbstract(typeCondition?.name.value)) return true;
          pending.addAll(selectionSet.selections);
        case FragmentSpread(:final name):
          final FragmentDefinition? fragment = fragments[name.value];
          if (fragment == null || !visited.add(name.value)) continue;
          if (_isAbstract(fragment.typeCondition.name.value)) return true;
          pending.addAll(fragment.selectionSet.selections);
      }
    }
    return false;
  }

  bool _isAbstract(String? typeName) =>
      switch (typeName == null ? null : schema.typeNamed(typeName)) {
        InterfaceType() || UnionType() => true,
        _ => false,
      };
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
