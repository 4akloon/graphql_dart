// Ported from graphql-js src/language/__tests__/visitor-test.ts; see
// mapping/language.csv.
import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../../support/parser_port.dart';
import '../../support/visit_recorder.dart';

void main() {
  const port = ParserPort();
  const walker = AstWalker();

  bool isField(Node node, String name) =>
      node is Field && node.name.value == name;

  bool isName(Node node, String value) => node is Name && node.value == value;

  group('Visitor', () {
    test('handles empty visitor', () {
      final ast = port.document('{ a }');
      expect(() => walker.walk(ast, const _EmptyVisitor()), returnsNormally);
    });

    // Adapted: AstTransformer edits a tree, bottom-up; removing a node
    // there gives the tree graphql-js gets from removing it on enter.
    test('allows for editing on enter', () {
      final ast = port.document('{ a, b, c { a, b, c } }');
      final editedAst = _Remove(
        (node) => isField(node, 'b'),
      ).transform(ast);

      expect(
        ast.isEquivalentTo(port.document('{ a, b, c { a, b, c } }')),
        isTrue,
      );
      expect(
        editedAst?.isEquivalentTo(port.document('{ a,    c { a,    c } }')),
        isTrue,
      );
    });

    // Adapted: AstTransformer edits a tree, bottom-up, which is graphql-js's
    // editing on leave.
    test('allows for editing on leave', () {
      final ast = port.document('{ a, b, c { a, b, c } }');
      final editedAst = _Remove(
        (node) => isField(node, 'b'),
      ).transform(ast);

      expect(
        ast.isEquivalentTo(port.document('{ a, b, c { a, b, c } }')),
        isTrue,
      );
      expect(
        editedAst?.isEquivalentTo(port.document('{ a,    c { a,    c } }')),
        isTrue,
      );
    });

    test('allows skipping a sub-tree', () {
      final visited = <List<Object?>>[];

      final ast = port.document('{ a, b { x }, c }');
      walker.walk(
        ast,
        VisitRecorder(
          visited,
          decide: (node) =>
              isField(node, 'b') ? VisitAction.skip : VisitAction.next,
        ),
      );

      expect(visited, [
        ['enter', 'Document', null],
        ['enter', 'OperationDefinition', null],
        ['enter', 'SelectionSet', null],
        ['enter', 'Field', null],
        ['enter', 'Name', 'a'],
        ['leave', 'Name', 'a'],
        ['leave', 'Field', null],
        ['enter', 'Field', null],
        ['enter', 'Field', null],
        ['enter', 'Name', 'c'],
        ['leave', 'Name', 'c'],
        ['leave', 'Field', null],
        ['leave', 'SelectionSet', null],
        ['leave', 'OperationDefinition', null],
        ['leave', 'Document', null],
      ]);
    });

    test('allows early exit while visiting', () {
      final visited = <List<Object?>>[];

      final ast = port.document('{ a, b { x }, c }');
      walker.walk(
        ast,
        VisitRecorder(
          visited,
          decide: (node) =>
              isName(node, 'x') ? VisitAction.stop : VisitAction.next,
        ),
      );

      expect(visited, [
        ['enter', 'Document', null],
        ['enter', 'OperationDefinition', null],
        ['enter', 'SelectionSet', null],
        ['enter', 'Field', null],
        ['enter', 'Name', 'a'],
        ['leave', 'Name', 'a'],
        ['leave', 'Field', null],
        ['enter', 'Field', null],
        ['enter', 'Name', 'b'],
        ['leave', 'Name', 'b'],
        ['enter', 'SelectionSet', null],
        ['enter', 'Field', null],
        ['enter', 'Name', 'x'],
      ]);
    });

    // Adapted: a visitor tells kinds apart with a switch in enter and
    // leave instead of graphql-js's per-kind functions.
    test('allows a named functions visitor API', () {
      final visited = <List<Object?>>[];

      final ast = port.document('{ a, b { x }, c }');
      walker.walk(ast, _NamesAndSelectionSets(visited));

      expect(visited, [
        ['enter', 'SelectionSet', null],
        ['enter', 'Name', 'a'],
        ['enter', 'Name', 'b'],
        ['enter', 'SelectionSet', null],
        ['enter', 'Name', 'x'],
        ['leave', 'SelectionSet', null],
        ['enter', 'Name', 'c'],
        ['leave', 'SelectionSet', null],
      ]);
    });

    group('visitInParallel', () {
      // Note: nearly identical to the above test of the same test but
      // using visitInParallel.
      test('allows skipping a sub-tree', () {
        final visited = <List<Object?>>[];

        final ast = port.document('{ a, b { x }, c }');
        walker.walk(
          ast,
          ParallelVisitor([
            VisitRecorder(
              visited,
              decide: (node) =>
                  isField(node, 'b') ? VisitAction.skip : VisitAction.next,
            ),
          ]),
        );

        expect(visited, [
          ['enter', 'Document', null],
          ['enter', 'OperationDefinition', null],
          ['enter', 'SelectionSet', null],
          ['enter', 'Field', null],
          ['enter', 'Name', 'a'],
          ['leave', 'Name', 'a'],
          ['leave', 'Field', null],
          ['enter', 'Field', null],
          ['enter', 'Field', null],
          ['enter', 'Name', 'c'],
          ['leave', 'Name', 'c'],
          ['leave', 'Field', null],
          ['leave', 'SelectionSet', null],
          ['leave', 'OperationDefinition', null],
          ['leave', 'Document', null],
        ]);
      });

      test('allows skipping different sub-trees', () {
        final visited = <List<Object?>>[];

        final ast = port.document('{ a { x }, b { y} }');
        walker.walk(
          ast,
          ParallelVisitor([
            VisitRecorder(
              visited,
              label: 'no-a',
              decide: (node) =>
                  isField(node, 'a') ? VisitAction.skip : VisitAction.next,
            ),
            VisitRecorder(
              visited,
              label: 'no-b',
              decide: (node) =>
                  isField(node, 'b') ? VisitAction.skip : VisitAction.next,
            ),
          ]),
        );

        expect(visited, [
          ['no-a', 'enter', 'Document', null],
          ['no-b', 'enter', 'Document', null],
          ['no-a', 'enter', 'OperationDefinition', null],
          ['no-b', 'enter', 'OperationDefinition', null],
          ['no-a', 'enter', 'SelectionSet', null],
          ['no-b', 'enter', 'SelectionSet', null],
          ['no-a', 'enter', 'Field', null],
          ['no-b', 'enter', 'Field', null],
          ['no-b', 'enter', 'Name', 'a'],
          ['no-b', 'leave', 'Name', 'a'],
          ['no-b', 'enter', 'SelectionSet', null],
          ['no-b', 'enter', 'Field', null],
          ['no-b', 'enter', 'Name', 'x'],
          ['no-b', 'leave', 'Name', 'x'],
          ['no-b', 'leave', 'Field', null],
          ['no-b', 'leave', 'SelectionSet', null],
          ['no-b', 'leave', 'Field', null],
          ['no-a', 'enter', 'Field', null],
          ['no-b', 'enter', 'Field', null],
          ['no-a', 'enter', 'Name', 'b'],
          ['no-a', 'leave', 'Name', 'b'],
          ['no-a', 'enter', 'SelectionSet', null],
          ['no-a', 'enter', 'Field', null],
          ['no-a', 'enter', 'Name', 'y'],
          ['no-a', 'leave', 'Name', 'y'],
          ['no-a', 'leave', 'Field', null],
          ['no-a', 'leave', 'SelectionSet', null],
          ['no-a', 'leave', 'Field', null],
          ['no-a', 'leave', 'SelectionSet', null],
          ['no-b', 'leave', 'SelectionSet', null],
          ['no-a', 'leave', 'OperationDefinition', null],
          ['no-b', 'leave', 'OperationDefinition', null],
          ['no-a', 'leave', 'Document', null],
          ['no-b', 'leave', 'Document', null],
        ]);
      });

      // Note: nearly identical to the above test of the same test but
      // using visitInParallel.
      test('allows early exit while visiting', () {
        final visited = <List<Object?>>[];

        final ast = port.document('{ a, b { x }, c }');
        walker.walk(
          ast,
          ParallelVisitor([
            VisitRecorder(
              visited,
              decide: (node) =>
                  isName(node, 'x') ? VisitAction.stop : VisitAction.next,
            ),
          ]),
        );

        expect(visited, [
          ['enter', 'Document', null],
          ['enter', 'OperationDefinition', null],
          ['enter', 'SelectionSet', null],
          ['enter', 'Field', null],
          ['enter', 'Name', 'a'],
          ['leave', 'Name', 'a'],
          ['leave', 'Field', null],
          ['enter', 'Field', null],
          ['enter', 'Name', 'b'],
          ['leave', 'Name', 'b'],
          ['enter', 'SelectionSet', null],
          ['enter', 'Field', null],
          ['enter', 'Name', 'x'],
        ]);
      });

      test('allows early exit from different points', () {
        final visited = <List<Object?>>[];

        final ast = port.document('{ a { y }, b { x } }');
        walker.walk(
          ast,
          ParallelVisitor([
            _NeverLeaves(
              visited,
              label: 'break-a',
              decide: (node) =>
                  isName(node, 'a') ? VisitAction.stop : VisitAction.next,
            ),
            VisitRecorder(
              visited,
              label: 'break-b',
              decide: (node) =>
                  isName(node, 'b') ? VisitAction.stop : VisitAction.next,
            ),
          ]),
        );

        expect(visited, [
          ['break-a', 'enter', 'Document', null],
          ['break-b', 'enter', 'Document', null],
          ['break-a', 'enter', 'OperationDefinition', null],
          ['break-b', 'enter', 'OperationDefinition', null],
          ['break-a', 'enter', 'SelectionSet', null],
          ['break-b', 'enter', 'SelectionSet', null],
          ['break-a', 'enter', 'Field', null],
          ['break-b', 'enter', 'Field', null],
          ['break-a', 'enter', 'Name', 'a'],
          ['break-b', 'enter', 'Name', 'a'],
          ['break-b', 'leave', 'Name', 'a'],
          ['break-b', 'enter', 'SelectionSet', null],
          ['break-b', 'enter', 'Field', null],
          ['break-b', 'enter', 'Name', 'y'],
          ['break-b', 'leave', 'Name', 'y'],
          ['break-b', 'leave', 'Field', null],
          ['break-b', 'leave', 'SelectionSet', null],
          ['break-b', 'leave', 'Field', null],
          ['break-b', 'enter', 'Field', null],
          ['break-b', 'enter', 'Name', 'b'],
        ]);
      });
    });
  });
}

/// A visitor that keeps the default methods: graphql-js's `{}`.
final class _EmptyVisitor extends AstVisitor {
  const _EmptyVisitor();
}

/// Removes every node that [matches].
final class _Remove extends AstTransformer {
  _Remove(this.matches);

  final bool Function(Node node) matches;

  @override
  Node? rewrite(Node node) => matches(node) ? null : node;
}

/// graphql-js's `{ Name(node) {...}, SelectionSet: { enter, leave } }`.
final class _NamesAndSelectionSets extends VisitRecorder {
  _NamesAndSelectionSets(super.visited);

  @override
  VisitAction enter(Node node) {
    if (node is Name || node is SelectionSet) {
      visited.add(entry('enter', node));
    }
    return VisitAction.next;
  }

  @override
  void leave(Node node) {
    if (node is SelectionSet) {
      visited.add(entry('leave', node));
    }
  }
}

/// A recorder whose `leave` must not be called.
final class _NeverLeaves extends VisitRecorder {
  _NeverLeaves(super.visited, {super.label, super.decide});

  @override
  void leave(Node node) => fail('Should not be called');
}
