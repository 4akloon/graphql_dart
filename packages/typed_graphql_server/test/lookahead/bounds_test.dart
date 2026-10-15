import 'package:test/test.dart';
import 'package:typed_graphql/typed_graphql.dart';
import 'package:typed_graphql_server/typed_graphql_server.dart';

import 'bounds_fixture.dart';

void main() {
  final f = BoundsFixture();

  // `fragment F0 on Chain { a: next {...F1} b: next(i: 2) {...F1} } ...`
  // down to `fragment F30 on Chain { id }`: [second] is the arguments of
  // the `b` field.
  String fanOut(String second) {
    final out = StringBuffer('{ chain { ...F0 } }\n');
    for (var n = 0; n < 30; n++) {
      out.writeln(
        'fragment F$n on Chain { a: next {...F${n + 1}} '
        'b: next$second {...F${n + 1}} }',
      );
    }
    out.writeln('fragment F30 on Chain { id }');
    return out.toString();
  }

  group('an abstract type', () {
    // `{ node { parent { parent { ... { id } } } } }`, twelve levels of an
    // interface with five implementations: 5^12 plans without the dedupe.
    final query = '{ node ${'{ parent ' * 12}{ id }${' }' * 12} }';

    test('costs its distinct nodes, not the product per level', () async {
      final clock = Stopwatch()..start();
      final selection = await f.selection('node', query);
      final read = [
        selection.fields.length,
        selection.has('${'parent.' * 12}id'),
        selection.has('${'parent.' * 13}id'),
        selection.fingerprint,
      ];
      expect(clock.elapsedMilliseconds, lessThan(1000));
      expect(read, [
        1,
        true,
        false,
        '${'parent{' * 12}id${'}' * 12}',
      ]);
    });
  });

  group('one response key', () {
    test('over different fields is as many selected fields', () async {
      final selection = await f.selection(
        'fruit',
        '{ fruit { ... on Apple { k: weight } ... on Pear { k: length } } }',
      );
      expect(
        [for (final field in selection.fields) field.name],
        ['weight', 'length'],
      );
    });

    test('over the same field is one selected field', () async {
      final selection = await f.selection(
        'fruit',
        '{ fruit { ... on Apple { k: weight } ... on Pear { k: weight } } }',
      );
      expect(selection.fields.length, 1);
    });
  });

  group('aliases through fragments', () {
    test('with the same arguments fingerprint in linear time', () async {
      final clock = Stopwatch()..start();
      final selection = await f.selection('chain', fanOut(''));
      final read = [
        selection.fingerprint,
        selection.has('${'next.' * 30}id'),
      ];
      expect(clock.elapsedMilliseconds, lessThan(1000));
      expect(read, ['${'next{' * 30}id${'}' * 30}', true]);
    });

    test('with other arguments are refused by maxSteps as GQL337', () async {
      final clock = Stopwatch()..start();
      f.onCall = (info) => info.selection.fingerprint;
      final payload = await f.run(
        fanOut('(i: 2)'),
        options: const ExecutionOptions(maxSteps: 1000),
      );
      final error = (payload as ExecutionResult).errors.single;
      expect(clock.elapsedMilliseconds, lessThan(1000));
      expect(
        error.toJson()['extensions'],
        JsonObject({'code': const JsonString('GQL337')}),
      );
      expect(
        error.message,
        'Execution exceeds the limit of 1000 completed '
        'values.',
      );
    });

    test('with other arguments still fit a generous budget', () async {
      var text = '';
      f.onCall = (info) => text = info.selection.fingerprint;
      await f.run(
        '{ chain { ...F0 } }'
        'fragment F0 on Chain { a: next {...F1} b: next(i: 2) {...F1} }'
        'fragment F1 on Chain { id }',
      );
      expect(text, 'next(i:2){id},next{id}');
    });
  });
}
