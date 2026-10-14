import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';

void main() {
  const printer = Printer(isMinified: true);

  String print(Node? node) => node == null ? 'removed' : printer.print(node);

  test('keeps the instance of a tree where nothing changes', () {
    final document = Parsed('{ a { b } c(x: [1, 2]) }').document;
    expect(_Rewrite((node) => node).transform(document), same(document));
  });

  SelectionSet selectionSetOf(Node? node) => switch (node) {
    Document(definitions: [OperationDefinition(:final selectionSet)]) =>
      selectionSet,
    _ => fail('expected a document with one operation, got $node'),
  };

  test('replaces a node and leaves the original tree as it was', () {
    final document = Parsed('{ a b { x } }').document;
    final rewritten = _Rewrite(
      (node) => node is Name && node.value == 'x' ? const Name('y') : node,
    ).transform(document);
    expect(print(rewritten), '{a b{y}}');
    expect(print(document), '{a b{x}}');
  });

  test('rebuilds the changed branch and keeps the unchanged one', () {
    final document = Parsed('{ a b { x } }').document;
    final rewritten = _Rewrite(
      (node) => node is Name && node.value == 'x' ? const Name('y') : node,
    ).transform(document);
    final [fieldA, fieldB] = selectionSetOf(document).selections;
    final [newFieldA, newFieldB] = selectionSetOf(rewritten).selections;
    expect(newFieldA, same(fieldA));
    expect(newFieldB, isNot(same(fieldB)));
  });

  test('null removes a node from its list', () {
    final document = Parsed('{ a, b, c { a, b, c } }').document;
    final rewritten = _Rewrite(
      (node) => node is Field && node.name.value == 'b' ? null : node,
    ).transform(document);
    expect(print(rewritten), '{a c{a c}}');
  });

  test('null removes an optional child, such as an alias', () {
    final document = Parsed('{ b: a }').document;
    final rewritten = _Rewrite(
      (node) => node is Name && node.value == 'b' ? null : node,
    ).transform(document);
    expect(print(rewritten), '{a}');
  });

  test('removing the name of an aliased field is a StateError', () {
    final document = Parsed('{ b: a }').document;
    final transformer = _Rewrite(
      (node) => node is Name && node.value == 'a' ? null : node,
    );
    expect(() => transformer.transform(document), throwsStateError);
  });

  test('removing the name of a directive definition is a StateError', () {
    final document = Parsed('directive @foo on FIELD | QUERY').document;
    final transformer = _Rewrite(
      (node) => node is Name && node.value == 'foo' ? null : node,
    );
    expect(() => transformer.transform(document), throwsStateError);
  });

  test('removing a required child is a StateError', () {
    final document = Parsed('{ a(x: 1) }').document;
    final transformer = _Rewrite((node) => node is IntValue ? null : node);
    expect(() => transformer.transform(document), throwsStateError);
  });

  test('returns null when the root is removed', () {
    expect(_Rewrite((node) => null).transform(const Name('a')), isNull);
  });

  test('rewrite sees the children already rewritten', () {
    final seen = <String>[];
    _Rewrite((node) {
      if (node is Field) {
        seen.add(print(node));
      }
      return node is Name ? Name(node.value.toUpperCase()) : node;
    }).transform(Parsed('{ a { b } }').document);
    expect(seen, ['B', 'A{B}']);
  });

  test('adds __typename to every selection set, as code generation does', () {
    final document = Parsed('{ a { b } ... on T { c } }').document;
    expect(
      print(const _AddTypename().transform(document)),
      '{a{b __typename}...on T{c __typename}__typename}',
    );
  });

  test('rewrites a tree 100 000 levels deep without overflowing', () {
    Value value = const IntValue('1');
    for (var i = 0; i < 100000; i++) {
      value = ListValue([value]);
    }
    final rewritten = _Rewrite(
      (node) => node is IntValue ? const IntValue('2') : node,
    ).transform(value);
    var inner = rewritten;
    while (inner is ListValue) {
      inner = inner.values.single;
    }
    expect(
      inner,
      isA<IntValue>().having((literal) => literal.value, 'value', '2'),
    );
  });
}

/// A transformer that rewrites with [replace].
final class _Rewrite extends AstTransformer {
  _Rewrite(this.replace);

  final Node? Function(Node node) replace;

  @override
  Node? rewrite(Node node) => replace(node);
}

/// Adds a `__typename` field to each selection set that lacks one.
final class _AddTypename extends AstTransformer {
  const _AddTypename();

  @override
  Node? rewrite(Node node) {
    if (node case SelectionSet(:final selections)
        when !selections.any(_isTypename)) {
      return SelectionSet([
        ...selections,
        Field(null, const Name('__typename')),
      ]);
    }
    return node;
  }

  static bool _isTypename(Selection selection) =>
      selection is Field &&
      selection.alias == null &&
      selection.name.value == '__typename';
}
