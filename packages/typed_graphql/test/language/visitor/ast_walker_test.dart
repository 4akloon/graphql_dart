import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';
import 'visit_log.dart';

void main() {
  const walker = AstWalker();

  List<String> walk(String text, {String? skipAt, String? stopAt}) {
    final entries = <String>[];
    walker.walk(
      Parsed(text).document,
      VisitLog(entries, skipAt: skipAt, stopAt: stopAt),
    );
    return entries;
  }

  test('enters and leaves every node depth-first in children order', () {
    expect(walk('{ a(x: 1) }'), [
      'enter Document',
      'enter OperationDefinition',
      'enter SelectionSet',
      'enter Field a',
      'enter Name a',
      'leave Name a',
      'enter Argument',
      'enter Name x',
      'leave Name x',
      'enter IntValue 1',
      'leave IntValue 1',
      'leave Argument',
      'leave Field a',
      'leave SelectionSet',
      'leave OperationDefinition',
      'leave Document',
    ]);
  });

  test('skip passes over the children and does not leave the node', () {
    expect(walk('{ a { x } b }', skipAt: 'Field a'), [
      'enter Document',
      'enter OperationDefinition',
      'enter SelectionSet',
      'enter Field a',
      'enter Field b',
      'enter Name b',
      'leave Name b',
      'leave Field b',
      'leave SelectionSet',
      'leave OperationDefinition',
      'leave Document',
    ]);
  });

  test('stop ends the walk without leaving any node', () {
    expect(walk('{ a { x } b }', stopAt: 'Name x'), [
      'enter Document',
      'enter OperationDefinition',
      'enter SelectionSet',
      'enter Field a',
      'enter Name a',
      'leave Name a',
      'enter SelectionSet',
      'enter Field x',
      'enter Name x',
    ]);
  });

  test('a visitor with the default methods walks without effect', () {
    expect(
      () => walker.walk(Parsed('{ a }').document, const _DefaultVisitor()),
      returnsNormally,
    );
  });

  test('stop on the root enters nothing else', () {
    expect(walk('{ a }', stopAt: 'Document'), ['enter Document']);
  });

  test('walks a tree 100 000 levels deep without overflowing the stack', () {
    Value value = const IntValue('1');
    for (var i = 0; i < 100000; i++) {
      value = ListValue([value]);
    }
    var entered = 0;
    walker.walk(value, _Counter(() => entered++));
    expect(entered, 100001);
  });
}

/// A visitor that keeps the default [enter] and [leave].
final class _DefaultVisitor extends AstVisitor {
  const _DefaultVisitor();
}

/// A visitor that calls [onEnter] for each node it enters.
final class _Counter extends AstVisitor {
  _Counter(this.onEnter);

  final void Function() onEnter;

  @override
  VisitAction enter(Node node) {
    onEnter();
    return VisitAction.next;
  }
}
