import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';

import '../parser/parsed.dart';
import 'visit_log.dart';

void main() {
  const walker = AstWalker();

  /// The entries of [logs] after one parallel walk of [text].
  List<String> walkInParallel(String text, List<VisitLog> logs) {
    walker.walk(Parsed(text).document, ParallelVisitor(logs));
    return logs.first.entries;
  }

  /// The entries of [log] after walking [text] with it alone.
  List<String> walkAlone(String text, VisitLog log) {
    walker.walk(Parsed(text).document, log);
    return log.entries;
  }

  test('one visitor sees what it sees alone, skips included', () {
    const text = '{ a { x } b }';
    expect(
      walkInParallel(text, [VisitLog([], skipAt: 'Field a')]),
      walkAlone(text, VisitLog([], skipAt: 'Field a')),
    );
  });

  test('visitors skip different subtrees, each called in turn', () {
    final entries = <String>[];
    walkInParallel('{ a { x } b { y } }', [
      VisitLog(entries, label: 'no-a ', skipAt: 'Field a'),
      VisitLog(entries, label: 'no-b ', skipAt: 'Field b'),
    ]);
    expect(entries.where((entry) => entry.contains('Name')), [
      'no-b enter Name a',
      'no-b leave Name a',
      'no-b enter Name x',
      'no-b leave Name x',
      'no-a enter Name b',
      'no-a leave Name b',
      'no-a enter Name y',
      'no-a leave Name y',
    ]);
    expect(entries.take(2), ['no-a enter Document', 'no-b enter Document']);
    expect(entries.last, 'no-b leave Document');
  });

  test('a stopped visitor is not called again while the others go on', () {
    final entries = <String>[];
    walkInParallel('{ a { y } b { x } }', [
      VisitLog(entries, label: 'break-a ', stopAt: 'Name a'),
      VisitLog(entries, label: 'break-b ', stopAt: 'Name b'),
    ]);
    expect(
      entries.where((entry) => entry.startsWith('break-a')).last,
      'break-a enter Name a',
    );
    expect(entries.sublist(entries.length - 3), [
      'break-b leave Field a',
      'break-b enter Field b',
      'break-b enter Name b',
    ]);
  });

  test('enter skips a node that every running visitor skips', () {
    final field = Parsed('{ a }').document.definitions.single;
    final parallel = ParallelVisitor([
      VisitLog([], skipAt: 'OperationDefinition'),
      VisitLog([], skipAt: 'OperationDefinition'),
    ]);
    expect(parallel.enter(field), VisitAction.skip);
  });

  test('a visitor that skipped a node runs again after it', () {
    final entries = <String>[];
    walkInParallel('{ a b }', [
      VisitLog(entries, skipAt: 'Field a'),
      VisitLog(<String>[], skipAt: 'Field a'),
    ]);
    expect(entries, contains('enter Name b'));
  });

  test('enter stops the walk once every visitor stopped', () {
    final document = Parsed('{ a }').document;
    final parallel = ParallelVisitor([
      VisitLog([], stopAt: 'Document'),
      VisitLog([], stopAt: 'OperationDefinition'),
    ]);
    expect(parallel.enter(document), VisitAction.next);
    expect(parallel.enter(document.definitions.single), VisitAction.stop);
  });

  test('an empty list stops at once', () {
    expect(
      ParallelVisitor(const []).enter(const Name('a')),
      VisitAction.stop,
    );
  });
}
